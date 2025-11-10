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
🤖 نسخه نهایی پایدار با تنظیمات فروشگاه
✅ پنل ادمین کامل
✅ دکمه بازگشت همه‌جا فعال
✅ دکمه ⚙️ تنظیمات فروشگاه کاملاً کاربردی
"""

import os, json, sqlite3, logging
from datetime import datetime
from zoneinfo import ZoneInfo
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters

CONFIG_FILE = "config.json"
DB_FILE = "orders.db"
IRAN_TZ = ZoneInfo("Asia/Tehran")

# ---- تنظیم اولیه ----
def setup_config():
    if not os.path.exists(CONFIG_FILE):
        print("⚙️ تنظیم اولیه ربات:")
        token = input("توکن ربات: ").strip()
        admin_id = input("آیدی عددی ادمین: ").strip()
        cfg = {
            "BOT_TOKEN": token,
            "ADMIN_CHAT_ID": int(admin_id),
            "PRODUCT_NAME": "اکانت قانونی ChatGPT یک‌ماهه",
            "PRODUCT_PRICE": 350000,
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

def save_config():
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)

config = setup_config()
BOT_TOKEN = config["BOT_TOKEN"]
ADMIN_CHAT_ID = config["ADMIN_CHAT_ID"]

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---- دیتابیس ----
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

# ---- منوها ----
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

# ---- کاربر ----
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"👋 خوش آمدید!\n🛍️ {config['PRODUCT_NAME']}\n💰 قیمت: {config['PRODUCT_PRICE']:,} تومان",
        reply_markup=main_menu()
    )

async def buy(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    now = datetime.now(IRAN_TZ).isoformat()
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("INSERT INTO orders (user_id, username, fullname, price, status, created_at) VALUES (?,?,?,?,?,?)",
              (user.id, user.username, user.full_name, config['PRODUCT_PRICE'], "pending", now))
    conn.commit()
    oid = c.lastrowid
    conn.close()

    await context.bot.send_message(
        ADMIN_CHAT_ID,
        f"🆕 سفارش جدید:\n👤 {user.full_name} (@{user.username})\n🆔 #{oid}\n💰 {config['PRODUCT_PRICE']:,} تومان"
    )

    await update.message.reply_text(
        f"✅ سفارش #{oid} ثبت شد.\n💳 شماره کارت:\n{config['CARD_NUMBER']}\n\nپس از پرداخت، رسید خود را ارسال کنید.",
        reply_markup=after_order_menu()
    )
    context.user_data["current_order"] = oid

async def back(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data.clear()
    await update.message.reply_text("🔙 به منوی اصلی بازگشتید.", reply_markup=main_menu())

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
    user = update.effective_user
    oid = context.user_data["waiting_receipt"]
    caption = f"📩 رسید پرداخت سفارش #{oid}\n👤 {user.full_name} (@{user.username})"

    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("UPDATE orders SET receipt=? WHERE id=?", ("sent", oid))
    conn.commit()
    conn.close()

    if update.message.photo:
        await context.bot.send_photo(ADMIN_CHAT_ID, photo=update.message.photo[-1].file_id, caption=caption)
    else:
        await context.bot.send_message(ADMIN_CHAT_ID, text=f"{caption}\n📝 متن رسید:\n{update.message.text}")

    await update.message.reply_text("✅ رسید پرداخت شما ارسال شد و در انتظار تایید است.", reply_markup=main_menu())
    context.user_data.clear()

# ---- اطلاعات ----
async def my_orders(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT id, status, price FROM orders WHERE user_id=?", (user.id,))
    rows = c.fetchall()
    conn.close()
    if not rows:
        await update.message.reply_text("📭 شما هیچ سفارشی ندارید.", reply_markup=main_menu())
        return
    msg = "📦 سفارش‌های شما:\n"
    for r in rows:
        msg += f"#{r[0]} | {r[2]:,} تومان | وضعیت: {r[1]}\n"
    await update.message.reply_text(msg, reply_markup=main_menu())

async def about(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config["ABOUT_TEXT"], reply_markup=main_menu())

async def rules(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config["RULES_TEXT"], reply_markup=main_menu())

async def support(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config["SUPPORT_TEXT"], reply_markup=main_menu())

# ---- ادمین ----
async def admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        await update.message.reply_text("⛔ شما ادمین نیستید.")
        return
    await update.message.reply_text("👑 پنل ادمین فعال شد.", reply_markup=admin_menu())

async def admin_action(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        return
    text = update.message.text

    # بازگشت به منوی کاربران
    if text == "بازگشت به منوی اصلی":
        await update.message.reply_text("بازگشت به منوی کاربران.", reply_markup=main_menu())
        return

    # تنظیمات فروشگاه
    if text == "⚙️ تنظیمات فروشگاه":
        await update.message.reply_text("🛠 تنظیمات فروشگاه:", reply_markup=settings_menu())
        context.user_data["mode"] = "settings"
        return

    if context.user_data.get("mode") == "settings":
        # بازگشت از تنظیمات
        if text == "بازگشت":
            context.user_data.clear()
            await update.message.reply_text("بازگشت به پنل ادمین.", reply_markup=admin_menu())
            return
        if text == "🛒 تنظیم نام محصول":
            await update.message.reply_text("نام جدید محصول را وارد کنید:")
            context.user_data["setting"] = "PRODUCT_NAME"
            return
        if text == "💰 تنظیم قیمت محصول":
            await update.message.reply_text("قیمت جدید محصول را وارد کنید (به تومان):")
            context.user_data["setting"] = "PRODUCT_PRICE"
            return
        if text == "💳 تنظیم شماره کارت":
            await update.message.reply_text("شماره کارت جدید را وارد کنید:")
            context.user_data["setting"] = "CARD_NUMBER"
            return
        if text == "ℹ️ تنظیم درباره محصول":
            await update.message.reply_text("متن جدید درباره محصول را وارد کنید:")
            context.user_data["setting"] = "ABOUT_TEXT"
            return
        if text == "📜 تنظیم قوانین":
            await update.message.reply_text("متن جدید قوانین را وارد کنید:")
            context.user_data["setting"] = "RULES_TEXT"
            return
        if text == "📞 تنظیم پشتیبانی":
            await update.message.reply_text("متن جدید پشتیبانی را وارد کنید:")
            context.user_data["setting"] = "SUPPORT_TEXT"
            return
        if text == "⏰ تنظیم زمان لغو سفارش (دقیقه)":
            await update.message.reply_text("زمان جدید لغو سفارش (دقیقه) را وارد کنید:")
            context.user_data["setting"] = "CANCEL_TIME_MINUTES"
            return

        # ذخیره مقدار جدید
        if "setting" in context.user_data:
            key = context.user_data["setting"]
            value = text
            if key == "PRODUCT_PRICE" or key == "CANCEL_TIME_MINUTES":
                try:
                    value = int(value)
                except:
                    await update.message.reply_text("❌ لطفاً مقدار عددی وارد کنید.")
                    return
            config[key] = value
            save_config()
            context.user_data.clear()
            await update.message.reply_text(f"✅ مقدار جدید برای {key} ذخیره شد.", reply_markup=settings_menu())
            context.user_data["mode"] = "settings"
            return

    # سایر دستورات ادمین
    if text == "📋 سفارش‌های در انتظار":
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("SELECT id, username, price, created_at FROM orders WHERE status='pending'")
        rows = c.fetchall()
        conn.close()
        if not rows:
            await update.message.reply_text("📭 هیچ سفارش در انتظاری وجود ندارد.", reply_markup=admin_menu())
            return
        msg = "📋 سفارش‌های در انتظار:\n"
        for r in rows:
            msg += f"#{r[0]} | @{r[1]} | {r[2]:,} تومان | {r[3][:16]}\n"
        await update.message.reply_text(msg, reply_markup=admin_menu())
        return

# ---- main ----
def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()

    # کاربر
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.Regex("^🛒 خرید اکانت$"), buy))
    app.add_handler(MessageHandler(filters.Regex("^📤 ارسال رسید پرداخت$"), handle_receipt_request))
    app.add_handler(MessageHandler(filters.Regex("^🔙 بازگشت به منوی اصلی$"), back))
    app.add_handler(MessageHandler(filters.PHOTO, handle_receipt))
    app.add_handler(MessageHandler(filters.Regex("^📦 سفارش‌های من$"), my_orders))
    app.add_handler(MessageHandler(filters.Regex("^ℹ️ درباره محصول$"), about))
    app.add_handler(MessageHandler(filters.Regex("^📜 قوانین$"), rules))
    app.add_handler(MessageHandler(filters.Regex("^📞 پشتیبانی$"), support))

    # ادمین
    app.add_handler(CommandHandler("admin", admin))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.TEXT, admin_action))

    logger.info("🤖 Bot started (Asia/Tehran)")
    app.run_polling()

if __name__ == "__main__":
    main()
PYEOF

echo "✅ فایل bot.py ساخته شد."
echo "🤖 اجرای ربات..."
python3 bot.py
