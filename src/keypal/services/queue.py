import asyncio
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger(__name__)

# Handler signature: (user_id, message, **kwargs) -> str
Handler = Callable[..., Awaitable[str]]

_QueueItem = tuple[str, dict[str, Any], asyncio.Future[str]]


@dataclass
class _UserQueue:
    queue: asyncio.Queue[_QueueItem] = field(default_factory=asyncio.Queue)
    worker_running: bool = False


class MessageQueue:
    """Per-user message queue that processes messages in order.

    Each user gets their own queue so one user's slow request
    doesn't block others. Within a user, messages are processed
    sequentially to maintain conversation order.
    """

    def __init__(self, handler: Handler, max_concurrent_users: int = 10) -> None:
        self._handler = handler
        self._semaphore = asyncio.Semaphore(max_concurrent_users)
        self._user_queues: dict[int, _UserQueue] = {}

    async def enqueue(self, user_id: int, message: str, **kwargs: Any) -> str:
        """Add a message to the user's queue and wait for the result."""
        if user_id not in self._user_queues:
            self._user_queues[user_id] = _UserQueue()

        uq = self._user_queues[user_id]
        loop = asyncio.get_running_loop()
        future: asyncio.Future[str] = loop.create_future()
        await uq.queue.put((message, kwargs, future))

        if not uq.worker_running:
            uq.worker_running = True
            asyncio.create_task(self._process_user_queue(user_id))

        return await future

    async def _process_user_queue(self, user_id: int) -> None:
        uq = self._user_queues[user_id]
        try:
            while not uq.queue.empty():
                message, kwargs, future = await uq.queue.get()
                try:
                    async with self._semaphore:
                        result = await self._handler(user_id, message, **kwargs)
                    future.set_result(result)
                except Exception as e:
                    logger.exception("Error processing message for user %d", user_id)
                    if not future.done():
                        future.set_exception(e)
                finally:
                    uq.queue.task_done()
        finally:
            uq.worker_running = False
            if uq.queue.empty():
                del self._user_queues[user_id]

    @property
    def active_users(self) -> int:
        return len(self._user_queues)
