import asyncio
import json
import unittest

from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from gateway import Settings, create_app


def payload():
    return {
        "schema_version": 1, "question": "最近记录如何？",
        "context": {"today_count": 2, "last_7_days_count": 8, "invalid_event_count": 1,
                    "last_sync_at": None, "is_demo": True, "unknown_time_count": 1, "future_time_count": 0,
                    "total_count": 21, "daily_counts": [0, 1, 0, 2, 0, 0, 5]},
    }


class GatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.resources = []
        self.requests = []
        self.upstream_started = asyncio.Event()
        self.upstream_release = asyncio.Event()

    async def asyncTearDown(self):
        self.upstream_release.set()
        for resource in reversed(self.resources):
            await resource.close()

    async def gateway(self, **kwargs):
        client = TestClient(TestServer(create_app(Settings(**kwargs))))
        await client.start_server()
        self.resources.append(client)
        return client

    async def upstream(self, scenario="normal"):
        async def handler(request):
            ws = web.WebSocketResponse()
            await ws.prepare(request)
            hello = await ws.receive_json()
            self.requests.append({"headers": dict(request.headers), "hello": hello})
            await ws.send_json({"type": "tts", "state": "stop"})  # Startup notice.
            await ws.send_json({"type": "hello", "transport": "websocket", "session_id": "test-session"})
            prompt = await ws.receive_json()
            self.requests[-1]["prompt"] = prompt
            self.upstream_started.set()
            if scenario == "wait":
                await self.upstream_release.wait()
            if scenario == "invalid":
                await ws.send_str("private-token-and-upstream-error")
            elif scenario == "alert":
                await ws.send_json({"type": "alert", "message": "private-token"})
            elif scenario != "timeout":
                await ws.send_json({"type": "stt", "text": prompt["text"]})
                await ws.send_json({"type": "llm", "emotion": "happy"})
                if scenario != "empty":
                    for text in ["已读取摘要。", "共 8 次动作。"]:
                        await ws.send_json({"type": "tts", "state": "sentence_start", "text": text,
                                            "session_id": "other-session" if scenario == "wrong_session" else "test-session"})
                        await ws.send_bytes(b"discard-opus-audio")
                if scenario != "disconnect":
                    await ws.send_json({"type": "tts", "state": "stop", "session_id": "test-session"})
            if scenario == "timeout":
                await ws.receive()  # Client closes on total deadline.
            await ws.close()
            return ws

        app = web.Application()
        app.router.add_get("/xiaozhi/v1/", handler)
        server = TestServer(app)
        await server.start_server()
        self.resources.append(server)
        return str(server.make_url("/xiaozhi/v1/")).replace("http://", "ws://", 1)

    async def test_mock_is_explicit_and_health_does_not_claim_upstream_readiness(self):
        client = await self.gateway()
        response = await client.post("/v1/assistant/chat", json=payload())
        self.assertEqual(response.status, 200)
        result = await response.json()
        self.assertEqual(result["provider"], "mock")
        self.assertIn("未调用小智", result["answer"])
        self.assertIn("8", result["answer"])
        self.assertIn("21", result["answer"])
        health = await (await client.get("/healthz")).json()
        self.assertFalse(health["upstream_verified"])

    async def test_rejects_credentials_missing_and_does_not_echo_them(self):
        client = await self.gateway(token="gateway-private-code")
        response = await client.post("/v1/assistant/chat", json=payload())
        self.assertEqual(response.status, 401)
        self.assertNotIn("gateway-private-code", await response.text())
        response = await client.post("/v1/assistant/chat", json=payload(), headers={"Authorization": "Bearer gateway-private-code"})
        self.assertEqual(response.status, 200)

    async def test_rejects_raw_records_unknown_fields_invalid_counts_and_bad_date(self):
        client = await self.gateway()
        cases = []
        item = payload(); item["records"] = [{"device_id": "private"}]; cases.append(item)
        item = payload(); item["context"]["device_id"] = "private"; cases.append(item)
        item = payload(); item["context"]["today_count"] = True; cases.append(item)
        item = payload(); item["context"]["today_count"] = -1; cases.append(item)
        item = payload(); item["context"]["last_sync_at"] = "2026-09-23"; cases.append(item)
        item = payload(); item["question"] = "x" * 1001; cases.append(item)
        for item in cases:
            with self.subTest(item=item):
                response = await client.post("/v1/assistant/chat", json=item)
                self.assertEqual(response.status, 400)

    async def test_rejects_daily_series_that_disagrees_with_its_total(self):
        client = await self.gateway()
        cases = []
        item = payload(); item["context"]["daily_counts"] = [0, 1, 0, 2, 0, 0]; cases.append(item)
        item = payload(); item["context"]["daily_counts"] = "0" * 7; cases.append(item)
        item = payload(); item["context"]["daily_counts"] = [0, 1, 0, 2, 0, 0, True]; cases.append(item)
        item = payload(); item["context"]["daily_counts"] = [0, 1, 0, 2, 0, 0, -1]; cases.append(item)
        # Seven valid integers whose sum contradicts last_7_days_count.
        item = payload(); item["context"]["daily_counts"] = [0, 0, 0, 0, 0, 0, 0]; cases.append(item)
        for item in cases:
            with self.subTest(item=item):
                response = await client.post("/v1/assistant/chat", json=item)
                self.assertEqual(response.status, 400)

    async def test_rejects_large_body_before_upstream(self):
        client = await self.gateway()
        response = await client.post("/v1/assistant/chat", data="x" * 17000, headers={"Content-Type": "application/json"})
        self.assertEqual(response.status, 413)

    async def test_websocket_handshake_auth_text_prompt_and_sentence_assembly(self):
        url = await self.upstream()
        client = await self.gateway(mode="xiaozhi", ws_url=url, device_id="bridge-device", upstream_token="upstream-private")
        result = await (await client.post("/v1/assistant/chat", json=payload())).json()
        self.assertEqual(result["provider"], "xiaozhi")
        self.assertEqual(result["answer"], "已读取摘要。共 8 次动作。")
        request = self.requests[0]
        self.assertEqual(request["headers"]["Authorization"], "Bearer upstream-private")
        self.assertEqual(request["headers"]["Device-Id"], "bridge-device")
        self.assertFalse(request["hello"]["features"]["mcp"])
        self.assertEqual(request["prompt"]["state"], "detect")
        self.assertEqual(request["prompt"]["session_id"], "test-session")
        sent = json.loads(request["prompt"]["text"].split("\n", 1)[1])
        self.assertEqual(sent["context"], payload()["context"])
        self.assertNotIn("upstream-private", json.dumps(result))

    async def test_protocol_failures_never_return_partial_or_mock_success(self):
        for scenario in ["empty", "disconnect", "invalid", "alert", "wrong_session"]:
            with self.subTest(scenario=scenario):
                url = await self.upstream(scenario)
                client = await self.gateway(mode="xiaozhi", ws_url=url, device_id="bridge-device")
                response = await client.post("/v1/assistant/chat", json=payload())
                self.assertEqual(response.status, 502)
                text = await response.text()
                self.assertNotIn('"answer"', text)
                self.assertNotIn("private-token", text)

    async def test_total_timeout_and_single_upstream_request(self):
        url = await self.upstream("timeout")
        client = await self.gateway(mode="xiaozhi", ws_url=url, device_id="bridge-device", timeout=0.08)
        response = await client.post("/v1/assistant/chat", json=payload())
        self.assertEqual(response.status, 504)
        self.assertEqual(len(self.requests), 1)

    async def test_concurrent_requests_do_not_share_device_conversations(self):
        url = await self.upstream("wait")
        client = await self.gateway(mode="xiaozhi", ws_url=url, device_id="bridge-device")
        first = asyncio.create_task(client.post("/v1/assistant/chat", json=payload()))
        await asyncio.wait_for(self.upstream_started.wait(), 2)
        second = await client.post("/v1/assistant/chat", json=payload())
        self.assertEqual(second.status, 429)
        self.upstream_release.set()
        self.assertEqual((await first).status, 200)
        self.assertEqual(len(self.requests), 1)

    def test_external_binding_requires_gateway_auth_and_real_mode_requires_upstream(self):
        for settings in [Settings(host="0.0.0.0"), Settings(mode="xiaozhi"), Settings(token="bad\nheader")]:
            with self.assertRaises(ValueError):
                settings.validate()


if __name__ == "__main__":
    unittest.main()
