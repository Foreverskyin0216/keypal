"""Tests for utility/helper functions across the codebase."""

from keypal.services.chat import UsageStats, _tool_status


def test_tool_status_known() -> None:
    assert _tool_status("Read") == "~ reading ..."
    assert _tool_status("Bash") == "~ running ..."
    assert _tool_status("WebSearch") == "~ looking up ..."


def test_tool_status_unknown() -> None:
    result = _tool_status("SomeCustomTool")
    assert "SomeCustomTool" in result
    assert "~" in result


def test_usage_stats() -> None:
    stats = UsageStats()
    assert stats.total_cost_usd == 0.0
    assert stats.message_count == 0

    stats.record(0.05)
    assert stats.message_count == 1
    assert stats.total_cost_usd == 0.05

    stats.record(0.03)
    assert stats.message_count == 2
    assert abs(stats.total_cost_usd - 0.08) < 1e-10


def test_truncate() -> None:
    from keypal.channels.telegram.handlers.messages import _truncate

    # Short text unchanged
    assert _truncate("hello") == "hello"

    # Exactly at limit
    text_120 = "x" * 120
    assert _truncate(text_120, limit=120) == text_120

    # Over limit gets truncated
    text_200 = "x" * 200
    result = _truncate(text_200, limit=100)
    assert len(result) <= 100
    assert "truncated" in result


def test_cron_to_human() -> None:
    from keypal.channels.telegram.handlers.schedules import _cron_to_human

    assert _cron_to_human("0 9 * * *") == "daily 9:00"
    assert _cron_to_human("*/5 * * * *") == "every 5min"
    assert _cron_to_human("30 * * * *") == "every hour at :30"
    assert _cron_to_human("0 10 * * 1") == "Mon 10:00"
