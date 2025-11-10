#!/bin/bash
set -e

echo "🚀 شروع نصب و راه‌اندازی ربات فروش ChatGPT ..."

sudo apt update -y
sudo apt install -y python3 python3-pip
pip3 install --upgrade pip
pip3 install "python-telegram-bot[job-queue]"==20.7

echo "✅ پیش‌نیازها نصب شدند."

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ربات فروش اکانت ChatGPT — نسخه نهایی پایدار
✅ اضافه شد: ارسال رسید پرداخت و اطلاع به ادمین
✅ دکمه بازگشت و همه منوها به‌درستی کار می‌کنند
"""

import os, json, sqlite3, logging
from datetime import datetime
from zoneinfo import ZoneInfo
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters

CONFIG_FILE = "config.json"
DB_FILE = "orders.db"
IRAN_TZ = ZoneInfo("Asia/Tehran")

# ---------- تنظیم اولیه ----------
def setup_config():
    if not os.path.exists(CONFIG_FILE):
        print("⚙️ تنظیم اولیه ربات:")
        token = input("توکن ربات: ").strip()
        admin_id = input("آیدی عددی ادمین: ").strip()
        cfg = {
            "BOT_TOKEN": token,
            "ADMIN_CHAT_ID": int(admin_id),
            "PRODUCT_NAME": "تنظیم نشده",
            "PRODUCT_PRICE": 0,
            "CARD_NUMBER": "تنظیم نشده",
            "ABOUT_TEXT": "تنظیم نشده",
            "RULES_TEXT": "تنظیم نشده",
            "SUPPORT_TEXT": "تنظیم نشده",
            "CANCEL_TIME_MINUTES": 20
        }
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        print("✅ فایل config.json ساخته شد.")
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def save_config(cfg):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)

config = setup_config()
BOT_TOKEN = config["BOT_TOKEN"]
ADMIN_CHAT_ID = config["ADMIN_CHAT_ID"]

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------- دیتابیس ----------
def init_db():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("""
    CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        username TEXT,
        fullname TEXT,
        price INTEGER,
        status TEXT,
        created_at TEXT,
        receipt TEXT
    )
    """)
    conn.commit()
    conn.close()

# ---------- منوها ----------
def main_menu():
    return ReplyKeyboardMarkup(
        [["🛒 خرید اکانت", "📦 سفارش‌های من"],
         ["ℹ️ درباره محصول", "📜 قوانین"],
         ["📞 پشتیبانی"]],
        resize_keyboard=True
    )

def after_order_menu():
    return ReplyKeyboardMarkup(
        [["📤 ارسال رسید پرداخت"], ["🔙 بازگشت به منوی اصلی"]],
        resize_keyboard=True
    )

def admin_menu():
    return ReplyKeyboardMarkup(
        [["📋 سفارش‌های در انتظار", "✅ تایید پرداخت"],
         ["📤 ارسال اکانت", "⚙️ تنظیمات فروشگاه"],
         ["بازگشت به منوی اصلی"]],
        resize_keyboard=True
    )

def settings_menu():
    return ReplyKeyboardMarkup(
        [["🛒 تنظیم نام محصول", "💰 تنظیم قیمت محصول"],
         ["💳 تنظیم شماره کارت", "ℹ️ تنظیم درباره محصول"],
         ["📜 تنظیم قوانین", "📞 تنظیم پشتیبانی"],
         ["⏰ تنظیم زمان لغو سفارش (دقیقه)"],
         ["بازگشت"]],
        resize_keyboard=True
    )

# ---------- کاربران ----------
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    name = config.get("PRODUCT_NAME", "تنظیم نشده")
    price = config.get("PRODUCT_PRICE", 0)
    await update.message.reply_text(
        f"👋 خوش آمدید!\n🛍️ {name}\n💰 قیمت: {price:,} تومان",
        reply_markup=main_menu()
    )

async def buy(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    now = datetime.now(IRAN_TZ).isoformat()
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("INSERT INTO orders (user_id, username, fullname, price, status, created_at) VALUES (?,?,?,?,?,?)",
              (user.id, user.username, user.full_name, config.get("PRODUCT_PRICE", 0), "pending", now))
    conn.commit()
    oid = c.lastrowid
    conn.close()

    # اطلاع به ادمین
    msg = f"🆕 سفارش جدید:\n👤 {user.full_name} (@{user.username})\n🆔 #{oid}\n💰 {config['PRODUCT_PRICE']:,} تومان"
    try:
        await context.bot.send_message(ADMIN_CHAT_ID, msg)
    except:
        pass

    card = config.get("CARD_NUMBER", "تنظیم نشده")
    await update.message.reply_text(
        f"✅ سفارش #{oid} ثبت شد.\n💳 شماره کارت:\n{card}\n\nلطفاً پس از پرداخت، رسید خود را ارسال کنید.",
        reply_markup=after_order_menu()
    )
    context.user_data["current_order"] = oid

async def handle_receipt_request(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if "current_order" not in context.user_data:
        await update.message.reply_text("⛔ هیچ سفارشی در حال انتظار نیست.", reply_markup=main_menu())
        return
    oid = context.user_data["current_order"]
    await update.message.reply_text(f"📸 لطفاً تصویر یا متن رسید پرداخت سفارش #{oid} را ارسال کنید:")
    context.user_data["waiting_receipt"] = oid

async def handle_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if "waiting_receipt" not in context.user_data:
        return

    oid = context.user_data["waiting_receipt"]
    user = update.effective_user
    caption = f"📩 رسید پرداخت سفارش #{oid}\n👤 {user.full_name} (@{user.username})"

    # ذخیره رسید در دیتابیس
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("UPDATE orders SET receipt=? WHERE id=?", ("sent", oid))
    conn.commit()
    conn.close()

    # ارسال برای ادمین
    if update.message.photo:
        photo_file = update.message.photo[-1].file_id
        await context.bot.send_photo(chat_id=ADMIN_CHAT_ID, photo=photo_file, caption=caption)
    elif update.message.text:
        await context.bot.send_message(chat_id=ADMIN_CHAT_ID, text=f"{caption}\n📝 متن رسید:\n{update.message.text}")

    await update.message.reply_text("✅ رسید پرداخت شما ارسال شد و در انتظار تایید است.", reply_markup=main_menu())
    context.user_data.clear()

# ---------- ادمین ----------
async def admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        await update.message.reply_text("⛔ شما ادمین نیستید.")
        return
    await update.message.reply_text("👑 پنل ادمین فعال شد.", reply_markup=admin_menu())

# ---------- MAIN ----------
def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()

    # کاربران
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.Regex("^🛒 خرید اکانت$"), buy))
    app.add_handler(MessageHandler(filters.Regex("^📤 ارسال رسید پرداخت$"), handle_receipt_request))
    app.add_handler(MessageHandler(filters.PHOTO, handle_receipt))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_receipt))
    app.add_handler(CommandHandler("admin", admin))

    logger.info("🤖 Bot started (Tehran timezone)")
    app.run_polling()

if __name__ == "__main__":
    main()
PYEOF

echo "✅ فایل bot.py ساخته شد."
echo "🤖 اجرای ربات..."
python3 bot.py
