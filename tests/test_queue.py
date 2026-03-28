import asyncio

import pytest

from keypal.services.queue import MessageQueue


async def _echo_handler(user_id: int, message: str, **kwargs: object) -> str:
    return f"user={user_id}: {message}"


async def _slow_handler(user_id: int, message: str, **kwargs: object) -> str:
    await asyncio.sleep(0.05)
    return f"slow: {message}"


async def _failing_handler(user_id: int, message: str, **kwargs: object) -> str:
    raise ValueError("boom")


async def test_basic_enqueue() -> None:
    q = MessageQueue(handler=_echo_handler)
    result = await q.enqueue(1, "hello")
    assert result == "user=1: hello"


async def test_per_user_ordering() -> None:
    order: list[str] = []

    async def tracking_handler(user_id: int, message: str, **kwargs: object) -> str:
        await asyncio.sleep(0.01)
        order.append(f"{user_id}:{message}")
        return message

    q = MessageQueue(handler=tracking_handler)
    r1 = asyncio.create_task(q.enqueue(1, "a"))
    r2 = asyncio.create_task(q.enqueue(1, "b"))
    r3 = asyncio.create_task(q.enqueue(1, "c"))
    await asyncio.gather(r1, r2, r3)

    # Same user: processed in order
    assert order == ["1:a", "1:b", "1:c"]


async def test_different_users_concurrent() -> None:
    q = MessageQueue(handler=_slow_handler, max_concurrent_users=10)
    results = await asyncio.gather(
        q.enqueue(1, "a"),
        q.enqueue(2, "b"),
        q.enqueue(3, "c"),
    )
    assert set(results) == {"slow: a", "slow: b", "slow: c"}


async def test_handler_exception_propagates() -> None:
    q = MessageQueue(handler=_failing_handler)
    with pytest.raises(ValueError, match="boom"):
        await q.enqueue(1, "hello")


async def test_active_users() -> None:
    q = MessageQueue(handler=_echo_handler)
    assert q.active_users == 0
    await q.enqueue(1, "hi")
    # After processing, user queue should be cleaned up
    assert q.active_users == 0


async def test_kwargs_forwarded() -> None:
    received: dict[str, object] = {}

    async def handler(user_id: int, message: str, **kwargs: object) -> str:
        received.update(kwargs)
        return "ok"

    q = MessageQueue(handler=handler)
    await q.enqueue(1, "hi", foo="bar", count=42)
    assert received["foo"] == "bar"
    assert received["count"] == 42


async def test_concurrency_limit() -> None:
    concurrent = 0
    max_concurrent = 0

    async def counting_handler(user_id: int, message: str, **kwargs: object) -> str:
        nonlocal concurrent, max_concurrent
        concurrent += 1
        max_concurrent = max(max_concurrent, concurrent)
        await asyncio.sleep(0.02)
        concurrent -= 1
        return "ok"

    q = MessageQueue(handler=counting_handler, max_concurrent_users=2)
    await asyncio.gather(
        q.enqueue(1, "a"),
        q.enqueue(2, "b"),
        q.enqueue(3, "c"),
        q.enqueue(4, "d"),
    )
    assert max_concurrent <= 2
