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
ربات فروش اکانت ChatGPT — نسخه نهایی
✅ دکمه‌های کاربر و بازگشت‌ها اصلاح شدند
✅ لغو خودکار سفارش‌ها با زمان قابل تنظیم از پنل
"""

import os, json, sqlite3, logging
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters

CONFIG_FILE = "config.json"
DB_FILE = "orders.db"
IRAN_TZ = ZoneInfo("Asia/Tehran")

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
        created_at TEXT
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
        [["📋 سفارش‌های در انتظار", "⚙️ تنظیمات فروشگاه"],
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
    await update.message.reply_text(f"👋 خوش آمدید!\n🛍️ {name}\n💰 قیمت: {price:,} تومان", reply_markup=main_menu())

async def buy(update: Update, context: ContextTypes.DEFAULT_TYPE):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    user = update.effective_user
    now = datetime.now(IRAN_TZ).isoformat()
    c.execute("INSERT INTO orders (user_id, username, fullname, price, status, created_at) VALUES (?,?,?,?,?,?)",
              (user.id, user.username, user.full_name, config.get("PRODUCT_PRICE", 0), "pending", now))
    conn.commit()
    oid = c.lastrowid
    conn.close()
    card = config.get("CARD_NUMBER", "تنظیم نشده")
    await update.message.reply_text(
        f"✅ سفارش #{oid} ثبت شد.\n💳 شماره کارت:\n{card}\n\nپس از پرداخت، منتظر تایید ادمین باشید.",
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

async def back(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data.clear()
    if update.effective_user.id == ADMIN_CHAT_ID:
        await update.message.reply_text("بازگشت به پنل ادمین.", reply_markup=admin_menu())
    else:
        await update.message.reply_text("بازگشت به منوی اصلی.", reply_markup=main_menu())

# ---------- ادمین ----------
async def admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        await update.message.reply_text("⛔ فقط ادمین مجاز است.")
        return
    await update.message.reply_text("پنل ادمین فعال شد.", reply_markup=admin_menu())

async def settings(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        return
    await update.message.reply_text("⚙️ تنظیمات فروشگاه:", reply_markup=settings_menu())

async def admin_action(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        return
    text = update.message.text
    if text == "بازگشت":
        context.user_data.clear()
        await update.message.reply_text("بازگشت به پنل ادمین.", reply_markup=admin_menu())
        return

    actions = {
        "🛒 تنظیم نام محصول": "PRODUCT_NAME",
        "💰 تنظیم قیمت محصول": "PRODUCT_PRICE",
        "💳 تنظیم شماره کارت": "CARD_NUMBER",
        "ℹ️ تنظیم درباره محصول": "ABOUT_TEXT",
        "📜 تنظیم قوانین": "RULES_TEXT",
        "📞 تنظیم پشتیبانی": "SUPPORT_TEXT",
        "⏰ تنظیم زمان لغو سفارش (دقیقه)": "CANCEL_TIME_MINUTES"
    }

    if text in actions:
        context.user_data["set_key"] = actions[text]
        await update.message.reply_text("✏️ مقدار جدید را ارسال کنید:", reply_markup=settings_menu())
        return

    if "set_key" in context.user_data:
        key = context.user_data["set_key"]
        value = text.strip()
        if key in ["PRODUCT_PRICE", "CANCEL_TIME_MINUTES"]:
            try:
                value = int(value)
            except:
                await update.message.reply_text("❌ لطفاً فقط عدد وارد کنید.", reply_markup=settings_menu())
                return
        config[key] = value
        save_config(config)
        await update.message.reply_text(f"✅ مقدار جدید برای {key} ذخیره شد:\n{value}", reply_markup=settings_menu())
        context.user_data.clear()
        return

# ---------- لغو خودکار ----------
async def job_cancel_pending(context: ContextTypes.DEFAULT_TYPE):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT id, user_id, created_at FROM orders WHERE status='pending'")
    rows = c.fetchall()
    conn.close()
    now = datetime.now(IRAN_TZ)
    cancel_minutes = config.get("CANCEL_TIME_MINUTES", 20)
    for oid, uid, created in rows:
        created_dt = datetime.fromisoformat(created)
        if (now - created_dt).total_seconds() > cancel_minutes * 60:
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("UPDATE orders SET status='canceled' WHERE id=?", (oid,))
            conn.commit()
            conn.close()
            try:
                await context.bot.send_message(uid, f"⏰ سفارش #{oid} به دلیل عدم پرداخت در {cancel_minutes} دقیقه لغو شد.")
            except:
                pass

# ---------- MAIN ----------
def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()

    app.job_queue.run_repeating(job_cancel_pending, interval=120, first=10)

    # کاربرها
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.Regex("^🛒 خرید اکانت$"), buy))
    app.add_handler(MessageHandler(filters.Regex("^📦 سفارش‌های من$"), my_orders))
    app.add_handler(MessageHandler(filters.Regex("^ℹ️ درباره محصول$"), about))
    app.add_handler(MessageHandler(filters.Regex("^📜 قوانین$"), rules))
    app.add_handler(MessageHandler(filters.Regex("^📞 پشتیبانی$"), support))
    app.add_handler(MessageHandler(filters.Regex("^بازگشت به منوی اصلی$"), back))

    # ادمین
    app.add_handler(CommandHandler("admin", admin))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.Regex("^⚙️ تنظیمات فروشگاه$"), settings))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.Regex("^بازگشت به منوی اصلی$"), back))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.TEXT, admin_action))

    logger.info("🤖 Bot started (Tehran timezone)")
    app.run_polling()

if __name__ == "__main__":
    main()
PYEOF

echo "✅ فایل bot.py ساخته شد."
echo "🤖 اجرای ربات..."
python3 bot.py
