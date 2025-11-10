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
✅ پنل ادمین با /admin باز می‌شود
✅ دکمه‌های ارسال اکانت و تایید پرداخت فعال‌اند
✅ بازگشت از تنظیمات فروشگاه و منوی ادمین کاملاً درست کار می‌کند
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
        email TEXT,
        password TEXT
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
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    user = update.effective_user
    now = datetime.now(IRAN_TZ).isoformat()
    c.execute(
        "INSERT INTO orders (user_id, username, fullname, price, status, created_at) VALUES (?,?,?,?,?,?)",
        (user.id, user.username, user.full_name, config.get("PRODUCT_PRICE", 0), "pending", now)
    )
    conn.commit()
    oid = c.lastrowid
    conn.close()
    await update.message.reply_text(
        f"✅ سفارش #{oid} ثبت شد.\n💳 شماره کارت:\n{config.get('CARD_NUMBER', 'تنظیم نشده')}\n\nپس از پرداخت منتظر تایید ادمین باشید.",
        reply_markup=main_menu()
    )

async def my_orders(update: Update, context: ContextTypes.DEFAULT_TYPE):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT id, price, status, created_at FROM orders WHERE user_id=?", (update.effective_user.id,))
    rows = c.fetchall()
    conn.close()
    if not rows:
        await update.message.reply_text("📭 سفارشی یافت نشد.", reply_markup=main_menu())
        return
    msg = "📦 سفارش‌های شما:\n"
    for r in rows:
        created = datetime.fromisoformat(r[3]).astimezone(IRAN_TZ).strftime("%Y-%m-%d %H:%M")
        msg += f"#{r[0]} | {r[1]:,} تومان | {r[2]} | 🕒 {created}\n"
    await update.message.reply_text(msg, reply_markup=main_menu())

async def about(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config.get("ABOUT_TEXT", "تنظیم نشده"), reply_markup=main_menu())

async def rules(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config.get("RULES_TEXT", "تنظیم نشده"), reply_markup=main_menu())

async def support(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config.get("SUPPORT_TEXT", "تنظیم نشده"), reply_markup=main_menu())

# ---------- ادمین ----------
async def admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        await update.message.reply_text("⛔ شما ادمین نیستید.")
        return
    await update.message.reply_text("👑 پنل ادمین فعال شد.", reply_markup=admin_menu())

async def settings(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        return
    await update.message.reply_text("⚙️ تنظیمات فروشگاه:", reply_markup=settings_menu())
    context.user_data["in_settings"] = True

async def admin_action(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        return
    text = update.message.text

    # بازگشت از تنظیمات فروشگاه
    if text == "بازگشت" and context.user_data.get("in_settings"):
        context.user_data.clear()
        await update.message.reply_text("بازگشت به پنل ادمین.", reply_markup=admin_menu())
        return

    # بازگشت از پنل ادمین → منوی کاربران
    if text == "بازگشت به منوی اصلی":
        context.user_data.clear()
        await update.message.reply_text("بازگشت به منوی کاربران.", reply_markup=main_menu())
        return

    # تایید پرداخت
    if context.user_data.get("action") == "confirm":
        try:
            oid = int(text)
        except:
            await update.message.reply_text("❌ شماره سفارش معتبر نیست.", reply_markup=admin_menu())
            return
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("UPDATE orders SET status='paid' WHERE id=?", (oid,))
        conn.commit()
        conn.close()
        await update.message.reply_text(f"✅ سفارش #{oid} تایید شد.", reply_markup=admin_menu())
        context.user_data.clear()
        return

    # ارسال اکانت
    if context.user_data.get("action") == "send_account":
        try:
            oid = int(text)
        except:
            await update.message.reply_text("❌ شماره سفارش معتبر نیست.", reply_markup=admin_menu())
            return
        await update.message.reply_text("فرمت اکانت:\n`email@example.com | password123`", parse_mode="Markdown")
        context.user_data["action"] = f"send_{oid}"
        return

    if context.user_data.get("action", "").startswith("send_"):
        oid = int(context.user_data["action"].split("_")[1])
        try:
            email, password = [x.strip() for x in text.split("|")]
        except:
            await update.message.reply_text("❌ فرمت اشتباه است. از `email | password` استفاده کنید.", parse_mode="Markdown")
            return
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("UPDATE orders SET email=?, password=? WHERE id=?", (email, password, oid))
        conn.commit()
        conn.close()
        await update.message.reply_text(f"📤 اکانت برای سفارش #{oid} ارسال شد.", reply_markup=admin_menu())
        context.user_data.clear()
        return

# ---------- دستورات خاص ادمین ----------
async def confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id == ADMIN_CHAT_ID:
        await update.message.reply_text("شماره سفارش برای تایید را بفرستید:", reply_markup=admin_menu())
        context.user_data["action"] = "confirm"

async def send_account(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id == ADMIN_CHAT_ID:
        await update.message.reply_text("شماره سفارش برای ارسال اکانت را بفرستید:", reply_markup=admin_menu())
        context.user_data["action"] = "send_account"

# ---------- MAIN ----------
def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("admin", admin))
    app.add_handler(MessageHandler(filters.Regex("^🛒 خرید اکانت$"), buy))
    app.add_handler(MessageHandler(filters.Regex("^📦 سفارش‌های من$"), my_orders))
    app.add_handler(MessageHandler(filters.Regex("^ℹ️ درباره محصول$"), about))
    app.add_handler(MessageHandler(filters.Regex("^📜 قوانین$"), rules))
    app.add_handler(MessageHandler(filters.Regex("^📞 پشتیبانی$"), support))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.Regex("^⚙️ تنظیمات فروشگاه$"), settings))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.Regex("^✅ تایید پرداخت$"), confirm))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.Regex("^📤 ارسال اکانت$"), send_account))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.TEXT, admin_action))
    app.run_polling()

if __name__ == "__main__":
    main()
PYEOF

echo "✅ فایل bot.py ساخته شد."
echo "🤖 اجرای ربات..."
python3 bot.py
