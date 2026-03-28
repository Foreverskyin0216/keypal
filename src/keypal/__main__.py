import argparse
import logging

from keypal.config import settings


def main() -> None:
    parser = argparse.ArgumentParser(description="Keypal — your AI confidant")
    parser.add_argument(
        "--channel",
        choices=["telegram", "all"],
        default="all",
        help="Which channel to run (default: all)",
    )
    args = parser.parse_args()

    logging.basicConfig(level=settings.log_level, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    logger = logging.getLogger(__name__)

    channels = [args.channel] if args.channel != "all" else ["telegram"]

    if "telegram" in channels:
        from keypal.channels.telegram.app import create_telegram_app

        application = create_telegram_app()
        logger.info("Starting Keypal Telegram bot in polling mode...")
        application.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
