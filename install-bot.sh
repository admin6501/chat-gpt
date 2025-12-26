#!/bin/bash
set -e

echo "🚀 شروع نصب و راه‌اندازی ربات فروش ChatGPT با Docker ..."

if ! command -v docker &> /dev/null; then
    echo "📦 نصب Docker ..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl start docker
    sudo systemctl enable docker
    echo "✅ Docker نصب شد."
fi

BOT_DIR="chatgpt-seller-bot"
mkdir -p $BOT_DIR
cd $BOT_DIR

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, json, sqlite3, logging
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters

CONFIG_FILE = "/app/data/config.json"
DB_FILE = "/app/data/orders.db"
IRAN_TZ = ZoneInfo("Asia/Tehran")

def setup_config():
    if not os.path.exists(CONFIG_FILE):
        print("⚙️ تنظیم اولیه ربات:")
        token = os.environ.get("BOT_TOKEN") or input("توکن ربات: ").strip()
        admin_id = os.environ.get("ADMIN_ID") or input("آیدی عددی ادمین: ").strip()
        cfg = {
            "BOT_TOKEN": token,
            "ADMIN_CHAT_ID": int(admin_id),
            "PRODUCT_NAME": "اکانت قانونی ChatGPT یک‌ماهه",
            "PRODUCT_PRICE": 350000,
            "CARD_NUMBER": "تنظیم نشده",
            "ABOUT_TEXT": "تنظیم نشده",
            "RULES_TEXT": "تنظیم نشده",
            "SUPPORT_TEXT": "تنظیم نشده",
            "CANCEL_TIME_MINUTES": 20,
            "CHECK_INTERVAL_SECONDS": 60
        }
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
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

def init_db():
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("""
    CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        username TEXT,
        fullname TEXT,
        price INTEGER,
        original_price INTEGER,
        discount_code TEXT,
        discount_amount INTEGER DEFAULT 0,
        status TEXT,
        created_at TEXT,
        receipt TEXT
    )
    """)
    c.execute("""
    CREATE TABLE IF NOT EXISTS discount_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE,
        discount_type TEXT,
        discount_value INTEGER,
        max_usage_total INTEGER DEFAULT 0,
        max_usage_per_user INTEGER DEFAULT 0,
        expires_at TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT
    )
    """)
    c.execute("""
    CREATE TABLE IF NOT EXISTS discount_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        user_id INTEGER,
        order_id INTEGER,
        used_at TEXT
    )
    """)
    conn.commit()
    conn.close()

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

def buy_menu():
    return ReplyKeyboardMarkup(
        [["🎟️ دارم کد تخفیف", "❌ بدون کد تخفیف"],
         ["🔙 بازگشت به منوی اصلی"]],
        resize_keyboard=True
    )

def admin_menu():
    return ReplyKeyboardMarkup(
        [["📋 سفارش‌های در انتظار", "✅ تایید پرداخت"],
         ["📤 ارسال اکانت", "🎟️ مدیریت کد تخفیف"],
         ["⚙️ تنظیمات فروشگاه", "بازگشت به منوی اصلی"]],
        resize_keyboard=True
    )

def discount_menu():
    return ReplyKeyboardMarkup(
        [["➕ افزودن کد تخفیف", "📋 لیست کدهای تخفیف"],
         ["❌ غیرفعال کردن کد", "🗑️ حذف کد تخفیف"],
         ["📊 آمار استفاده کد"],
         ["🔙 بازگشت به پنل ادمین", "🏠 منوی اصلی"]],
        resize_keyboard=True
    )

def settings_menu():
    return ReplyKeyboardMarkup(
        [["🛒 تنظیم نام محصول", "💰 تنظیم قیمت محصول"],
         ["💳 تنظیم شماره کارت", "ℹ️ تنظیم درباره محصول"],
         ["📜 تنظیم قوانین", "📞 تنظیم پشتیبانی"],
         ["⏰ زمان لغو سفارش", "🔄 بازه چک سفارش‌ها"],
         ["🔙 بازگشت به پنل ادمین", "🏠 منوی اصلی"]],
        resize_keyboard=True
    )

def input_cancel_menu():
    return ReplyKeyboardMarkup([["❌ انصراف"]], resize_keyboard=True)

def user_input_cancel_menu():
    return ReplyKeyboardMarkup([["❌ انصراف و بازگشت"]], resize_keyboard=True)

def validate_discount_code(code, user_id):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT * FROM discount_codes WHERE code=? AND is_active=1", (code.upper(),))
    discount = c.fetchone()
    if not discount:
        conn.close()
        return None, "❌ کد تخفیف نامعتبر یا غیرفعال است."
    code_id, code_text, discount_type, discount_value, max_total, max_per_user, expires_at, is_active, created_at = discount
    if expires_at:
        expire_time = datetime.fromisoformat(expires_at)
        if datetime.now(IRAN_TZ) > expire_time:
            conn.close()
            return None, "❌ کد تخفیف منقضی شده است."
    if max_total > 0:
        c.execute("SELECT COUNT(*) FROM discount_usage WHERE code=?", (code.upper(),))
        total_used = c.fetchone()[0]
        if total_used >= max_total:
            conn.close()
            return None, "❌ ظرفیت استفاده از این کد تکمیل شده است."
    if max_per_user > 0:
        c.execute("SELECT COUNT(*) FROM discount_usage WHERE code=? AND user_id=?", (code.upper(), user_id))
        user_used = c.fetchone()[0]
        if user_used >= max_per_user:
            conn.close()
            return None, "❌ شما قبلاً از این کد تخفیف استفاده کرده‌اید."
    conn.close()
    return {"code": code_text, "type": discount_type, "value": discount_value, "max_total": max_total, "max_per_user": max_per_user}, None

def calculate_discounted_price(original_price, discount_info):
    if discount_info["type"] == "percent":
        discount_amount = int(original_price * discount_info["value"] / 100)
    else:
        discount_amount = discount_info["value"]
    final_price = max(0, original_price - discount_amount)
    return final_price, discount_amount

def record_discount_usage(code, user_id, order_id):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("INSERT INTO discount_usage (code, user_id, order_id, used_at) VALUES (?, ?, ?, ?)",
              (code.upper(), user_id, order_id, datetime.now(IRAN_TZ).isoformat()))
    conn.commit()
    conn.close()

async def cancel_expired_orders(context: ContextTypes.DEFAULT_TYPE):
    cancel_minutes = config.get("CANCEL_TIME_MINUTES", 20)
    cutoff_time = datetime.now(IRAN_TZ) - timedelta(minutes=cancel_minutes)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT id, user_id, fullname FROM orders WHERE status='pending' AND receipt IS NULL AND created_at < ?",
              (cutoff_time.isoformat(),))
    expired_orders = c.fetchall()
    for order in expired_orders:
        order_id, user_id, fullname = order
        c.execute("UPDATE orders SET status='cancelled' WHERE id=?", (order_id,))
        logger.info(f"Order #{order_id} cancelled")
        try:
            await context.bot.send_message(user_id, f"⛔ سفارش #{order_id} شما به دلیل عدم ارسال رسید پرداخت در مدت {cancel_minutes} دقیقه لغو شد.")
        except Exception as e:
            logger.error(f"Error notifying user: {e}")
        try:
            await context.bot.send_message(ADMIN_CHAT_ID, f"🔴 سفارش #{order_id} ({fullname}) به دلیل عدم پرداخت لغو شد.")
        except Exception as e:
            logger.error(f"Error notifying admin: {e}")
    conn.commit()
    conn.close()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"👋 خوش آمدید!\n🛍️ {config['PRODUCT_NAME']}\n💰 قیمت: {config['PRODUCT_PRICE']:,} تومان",
        reply_markup=main_menu()
    )

async def buy_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["buying"] = True
    await update.message.reply_text(
        f"🛒 خرید {config['PRODUCT_NAME']}\n💰 قیمت: {config['PRODUCT_PRICE']:,} تومان\n\n🎟️ آیا کد تخفیف دارید؟",
        reply_markup=buy_menu()
    )

async def buy_with_discount(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.user_data.get("buying"):
        await update.message.reply_text("لطفاً ابتدا روی خرید اکانت کلیک کنید.", reply_markup=main_menu())
        return
    context.user_data["waiting_discount_code"] = True
    await update.message.reply_text("🎟️ لطفاً کد تخفیف خود را وارد کنید:", reply_markup=user_input_cancel_menu())

async def buy_without_discount(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.user_data.get("buying"):
        await update.message.reply_text("لطفاً ابتدا روی خرید اکانت کلیک کنید.", reply_markup=main_menu())
        return
    await process_order(update, context, None)

async def process_order(update: Update, context: ContextTypes.DEFAULT_TYPE, discount_info):
    user = update.effective_user
    now = datetime.now(IRAN_TZ).isoformat()
    original_price = config['PRODUCT_PRICE']
    if discount_info:
        final_price, discount_amount = calculate_discounted_price(original_price, discount_info)
        discount_code = discount_info["code"]
    else:
        final_price = original_price
        discount_amount = 0
        discount_code = None
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("INSERT INTO orders (user_id, username, fullname, price, original_price, discount_code, discount_amount, status, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
              (user.id, user.username, user.full_name, final_price, original_price, discount_code, discount_amount, "pending", now))
    conn.commit()
    oid = c.lastrowid
    conn.close()
    if discount_code:
        record_discount_usage(discount_code, user.id, oid)
    admin_msg = f"🆕 سفارش جدید:\n👤 {user.full_name} (@{user.username})\n🆔 #{oid}\n"
    if discount_code:
        admin_msg += f"🎟️ کد تخفیف: {discount_code}\n💰 قیمت اصلی: {original_price:,} تومان\n💸 تخفیف: {discount_amount:,} تومان\n"
    admin_msg += f"💵 قیمت نهایی: {final_price:,} تومان"
    await context.bot.send_message(ADMIN_CHAT_ID, admin_msg)
    user_msg = f"✅ سفارش #{oid} ثبت شد.\n"
    if discount_code:
        user_msg += f"🎟️ کد تخفیف: {discount_code}\n💰 قیمت اصلی: {original_price:,} تومان\n💸 تخفیف: {discount_amount:,} تومان\n"
    user_msg += f"💵 مبلغ قابل پرداخت: {final_price:,} تومان\n\n💳 شماره کارت:\n{config['CARD_NUMBER']}\n\nپس از پرداخت، رسید خود را ارسال کنید.\n⏰ زمان پرداخت: {config['CANCEL_TIME_MINUTES']} دقیقه"
    await update.message.reply_text(user_msg, reply_markup=after_order_menu())
    context.user_data.clear()
    context.user_data["current_order"] = oid

async def handle_discount_code_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.user_data.get("waiting_discount_code"):
        return False
    user = update.effective_user
    code = update.message.text.strip()
    if code == "❌ انصراف و بازگشت":
        context.user_data.clear()
        await update.message.reply_text("🔙 به منوی اصلی بازگشتید.", reply_markup=main_menu())
        return True
    discount_info, error = validate_discount_code(code, user.id)
    if error:
        await update.message.reply_text(error, reply_markup=buy_menu())
        context.user_data["waiting_discount_code"] = False
        return True
    original_price = config['PRODUCT_PRICE']
    final_price, discount_amount = calculate_discounted_price(original_price, discount_info)
    if discount_info["type"] == "percent":
        discount_text = f"{discount_info['value']}%"
    else:
        discount_text = f"{discount_info['value']:,} تومان"
    await update.message.reply_text(
        f"✅ کد تخفیف معتبر است!\n\n🎟️ کد: {discount_info['code']}\n💯 میزان تخفیف: {discount_text}\n"
        f"💰 قیمت اصلی: {original_price:,} تومان\n💸 مبلغ تخفیف: {discount_amount:,} تومان\n"
        f"💵 قیمت نهایی: {final_price:,} تومان\n\nدر حال ثبت سفارش..."
    )
    context.user_data["waiting_discount_code"] = False
    await process_order(update, context, discount_info)
    return True

async def back(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data.clear()
    await update.message.reply_text("🔙 به منوی اصلی بازگشتید.", reply_markup=main_menu())

async def handle_receipt_request(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if "current_order" not in context.user_data:
        await update.message.reply_text("⛔ هیچ سفارشی در حال انتظار نیست.", reply_markup=main_menu())
        return
    oid = context.user_data["current_order"]
    await update.message.reply_text(f"📸 لطفاً تصویر یا متن رسید پرداخت سفارش #{oid} را ارسال کنید:", reply_markup=user_input_cancel_menu())
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

async def my_orders(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT id, status, price, original_price, discount_code, discount_amount FROM orders WHERE user_id=?", (user.id,))
    rows = c.fetchall()
    conn.close()
    if not rows:
        await update.message.reply_text("📭 شما هیچ سفارشی ندارید.", reply_markup=main_menu())
        return
    msg = "📦 سفارش‌های شما:\n"
    status_map = {"pending": "در انتظار", "paid": "پرداخت شده", "delivered": "تحویل داده شده", "cancelled": "لغو شده"}
    for r in rows:
        status_text = status_map.get(r[1], r[1])
        discount_info = ""
        if r[4]:
            discount_info = f" | تخفیف: {r[5]:,}"
        msg += f"#{r[0]} | {r[2]:,} تومان{discount_info} | {status_text}\n"
    await update.message.reply_text(msg, reply_markup=main_menu())

async def about(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config["ABOUT_TEXT"], reply_markup=main_menu())

async def rules(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config["RULES_TEXT"], reply_markup=main_menu())

async def support(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(config["SUPPORT_TEXT"], reply_markup=main_menu())

async def admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        await update.message.reply_text("⛔ شما ادمین نیستید.")
        return
    await update.message.reply_text("👑 پنل ادمین فعال شد.", reply_markup=admin_menu())

async def admin_action(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        return
    text = update.message.text

    if text == "بازگشت به منوی اصلی":
        context.user_data.clear()
        await update.message.reply_text("بازگشت به منوی کاربران.", reply_markup=main_menu())
        return

    if text == "🎟️ مدیریت کد تخفیف":
        await update.message.reply_text("🎟️ مدیریت کدهای تخفیف:", reply_markup=discount_menu())
        context.user_data["mode"] = "discount"
        return

    if text == "🏠 منوی اصلی":
        context.user_data.clear()
        await update.message.reply_text("🔙 به منوی اصلی بازگشتید.", reply_markup=main_menu())
        return

    if text == "❌ انصراف":
        mode = context.user_data.get("mode")
        context.user_data.clear()
        if mode in ["discount", "settings"]:
            context.user_data["mode"] = mode
            if mode == "discount":
                await update.message.reply_text("عملیات لغو شد.", reply_markup=discount_menu())
            else:
                await update.message.reply_text("عملیات لغو شد.", reply_markup=settings_menu())
        else:
            await update.message.reply_text("عملیات لغو شد.", reply_markup=admin_menu())
        return

    if context.user_data.get("mode") == "discount":
        if text == "🔙 بازگشت به پنل ادمین":
            context.user_data.clear()
            await update.message.reply_text("بازگشت به پنل ادمین.", reply_markup=admin_menu())
            return

        if text == "➕ افزودن کد تخفیف":
            await update.message.reply_text(
                "🎟️ برای افزودن کد تخفیف، اطلاعات را به فرمت زیر وارد کنید:\n\n"
                "```\nکد|نوع|مقدار|حداکثر_کل|حداکثر_هرکاربر|انقضا\n```\n\n"
                "📌 نوع: `percent` (درصدی) یا `amount` (مبلغی)\n"
                "📌 مقدار: عدد (درصد یا مبلغ به تومان)\n"
                "📌 حداکثر_کل: تعداد کل استفاده (0 = نامحدود)\n"
                "📌 حداکثر_هرکاربر: تعداد استفاده هر کاربر (0 = نامحدود)\n"
                "📌 انقضا: تعداد روز تا انقضا (0 = بدون انقضا)\n\n"
                "مثال درصدی:\n`SALE20|percent|20|100|1|30`\n\n"
                "مثال مبلغی:\n`OFF50K|amount|50000|0|2|0`",
                parse_mode="Markdown", reply_markup=input_cancel_menu()
            )
            context.user_data["discount_action"] = "add"
            return

        if text == "📋 لیست کدهای تخفیف":
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT code, discount_type, discount_value, max_usage_total, max_usage_per_user, expires_at, is_active FROM discount_codes ORDER BY id DESC")
            codes = c.fetchall()
            conn.close()
            if not codes:
                await update.message.reply_text("📭 هیچ کد تخفیفی وجود ندارد.", reply_markup=discount_menu())
                return
            msg = "📋 لیست کدهای تخفیف:\n\n"
            for code in codes:
                code_text, dtype, dvalue, max_total, max_per_user, expires, is_active = code
                type_text = f"{dvalue}%" if dtype == "percent" else f"{dvalue:,} تومان"
                status = "✅ فعال" if is_active else "❌ غیرفعال"
                expire_text = expires[:10] if expires else "بدون انقضا"
                max_total_text = str(max_total) if max_total > 0 else "∞"
                max_per_user_text = str(max_per_user) if max_per_user > 0 else "∞"
                msg += f"🎟️ {code_text}\n   💯 {type_text} | {status}\n   📊 کل: {max_total_text} | هرکاربر: {max_per_user_text}\n   📅 انقضا: {expire_text}\n\n"
            await update.message.reply_text(msg, reply_markup=discount_menu())
            return

        if text == "❌ غیرفعال کردن کد":
            await update.message.reply_text("🎟️ کد تخفیف مورد نظر برای غیرفعال کردن را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["discount_action"] = "deactivate"
            return

        if text == "📊 آمار استفاده کد":
            await update.message.reply_text("🎟️ کد تخفیف مورد نظر برای مشاهده آمار را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["discount_action"] = "stats"
            return

        if text == "🗑️ حذف کد تخفیف":
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT code, discount_type, discount_value, is_active FROM discount_codes ORDER BY id DESC")
            codes = c.fetchall()
            conn.close()
            if not codes:
                await update.message.reply_text("📭 هیچ کد تخفیفی برای حذف وجود ندارد.", reply_markup=discount_menu())
                return
            msg = "🗑️ لیست کدهای تخفیف برای حذف:\n\n"
            for code in codes:
                code_text, dtype, dvalue, is_active = code
                type_text = f"{dvalue}%" if dtype == "percent" else f"{dvalue:,} تومان"
                status = "✅" if is_active else "❌"
                msg += f"{status} {code_text} | {type_text}\n"
            msg += "\n🎟️ کد تخفیف مورد نظر برای حذف را وارد کنید:"
            await update.message.reply_text(msg, reply_markup=input_cancel_menu())
            context.user_data["discount_action"] = "delete"
            return

        if context.user_data.get("discount_action") == "add":
            try:
                parts = text.strip().split("|")
                if len(parts) != 6:
                    raise ValueError("فرمت نادرست")
                code = parts[0].upper().strip()
                discount_type = parts[1].lower().strip()
                discount_value = int(parts[2])
                max_total = int(parts[3])
                max_per_user = int(parts[4])
                expire_days = int(parts[5])
                if discount_type not in ["percent", "amount"]:
                    raise ValueError("نوع تخفیف باید percent یا amount باشد")
                if discount_type == "percent" and (discount_value < 1 or discount_value > 100):
                    raise ValueError("درصد تخفیف باید بین 1 تا 100 باشد")
                expires_at = None
                if expire_days > 0:
                    expires_at = (datetime.now(IRAN_TZ) + timedelta(days=expire_days)).isoformat()
                conn = sqlite3.connect(DB_FILE)
                c = conn.cursor()
                c.execute("INSERT INTO discount_codes (code, discount_type, discount_value, max_usage_total, max_usage_per_user, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                          (code, discount_type, discount_value, max_total, max_per_user, expires_at, datetime.now(IRAN_TZ).isoformat()))
                conn.commit()
                conn.close()
                type_text = f"{discount_value}%" if discount_type == "percent" else f"{discount_value:,} تومان"
                max_total_text = str(max_total) if max_total > 0 else "نامحدود"
                max_per_user_text = str(max_per_user) if max_per_user > 0 else "نامحدود"
                expire_text = f"{expire_days} روز" if expire_days > 0 else "بدون انقضا"
                await update.message.reply_text(
                    f"✅ کد تخفیف ایجاد شد!\n\n🎟️ کد: {code}\n💯 تخفیف: {type_text}\n📊 حداکثر کل: {max_total_text}\n👤 حداکثر هر کاربر: {max_per_user_text}\n📅 اعتبار: {expire_text}",
                    reply_markup=discount_menu()
                )
                context.user_data["discount_action"] = None
                return
            except sqlite3.IntegrityError:
                await update.message.reply_text("❌ این کد تخفیف قبلاً وجود دارد.", reply_markup=discount_menu())
                context.user_data["discount_action"] = None
                return
            except Exception as e:
                await update.message.reply_text(f"❌ خطا: {str(e)}\n\nلطفاً فرمت صحیح را رعایت کنید.", reply_markup=discount_menu())
                context.user_data["discount_action"] = None
                return

        if context.user_data.get("discount_action") == "deactivate":
            code = text.strip().upper()
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("UPDATE discount_codes SET is_active=0 WHERE code=?", (code,))
            if c.rowcount > 0:
                await update.message.reply_text(f"✅ کد تخفیف {code} غیرفعال شد.", reply_markup=discount_menu())
            else:
                await update.message.reply_text("❌ کد تخفیف یافت نشد.", reply_markup=discount_menu())
            conn.commit()
            conn.close()
            context.user_data["discount_action"] = None
            return

        if context.user_data.get("discount_action") == "delete":
            code = text.strip().upper()
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT id FROM discount_codes WHERE code=?", (code,))
            if not c.fetchone():
                await update.message.reply_text("❌ کد تخفیف یافت نشد.", reply_markup=discount_menu())
                conn.close()
                context.user_data["discount_action"] = None
                return
            c.execute("DELETE FROM discount_usage WHERE code=?", (code,))
            c.execute("DELETE FROM discount_codes WHERE code=?", (code,))
            conn.commit()
            conn.close()
            await update.message.reply_text(f"🗑️ کد تخفیف {code} و تمام سوابق استفاده آن حذف شد.", reply_markup=discount_menu())
            context.user_data["discount_action"] = None
            return

        if context.user_data.get("discount_action") == "stats":
            code = text.strip().upper()
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT discount_type, discount_value, max_usage_total, max_usage_per_user FROM discount_codes WHERE code=?", (code,))
            code_info = c.fetchone()
            if not code_info:
                await update.message.reply_text("❌ کد تخفیف یافت نشد.", reply_markup=discount_menu())
                conn.close()
                context.user_data["discount_action"] = None
                return
            c.execute("SELECT COUNT(*) FROM discount_usage WHERE code=?", (code,))
            total_usage = c.fetchone()[0]
            c.execute("SELECT COUNT(DISTINCT user_id) FROM discount_usage WHERE code=?", (code,))
            unique_users = c.fetchone()[0]
            c.execute("SELECT SUM(discount_amount) FROM orders WHERE discount_code=?", (code,))
            total_discount = c.fetchone()[0] or 0
            conn.close()
            type_text = f"{code_info[1]}%" if code_info[0] == "percent" else f"{code_info[1]:,} تومان"
            max_total_text = str(code_info[2]) if code_info[2] > 0 else "نامحدود"
            await update.message.reply_text(
                f"📊 آمار کد تخفیف {code}:\n\n💯 میزان تخفیف: {type_text}\n📈 تعداد استفاده: {total_usage} از {max_total_text}\n👥 کاربران یکتا: {unique_users}\n💰 مجموع تخفیف اعمال شده: {total_discount:,} تومان",
                reply_markup=discount_menu()
            )
            context.user_data["discount_action"] = None
            return

    if text == "⚙️ تنظیمات فروشگاه":
        await update.message.reply_text("🛠 تنظیمات فروشگاه:", reply_markup=settings_menu())
        context.user_data["mode"] = "settings"
        return

    if context.user_data.get("mode") == "settings":
        if text == "🔙 بازگشت به پنل ادمین":
            context.user_data.clear()
            await update.message.reply_text("بازگشت به پنل ادمین.", reply_markup=admin_menu())
            return
        if text == "🛒 تنظیم نام محصول":
            await update.message.reply_text("نام جدید محصول را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "PRODUCT_NAME"
            return
        if text == "💰 تنظیم قیمت محصول":
            await update.message.reply_text("قیمت جدید محصول را وارد کنید (به تومان):", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "PRODUCT_PRICE"
            return
        if text == "💳 تنظیم شماره کارت":
            await update.message.reply_text("شماره کارت جدید را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "CARD_NUMBER"
            return
        if text == "ℹ️ تنظیم درباره محصول":
            await update.message.reply_text("متن جدید درباره محصول را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "ABOUT_TEXT"
            return
        if text == "📜 تنظیم قوانین":
            await update.message.reply_text("متن جدید قوانین را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "RULES_TEXT"
            return
        if text == "📞 تنظیم پشتیبانی":
            await update.message.reply_text("متن جدید پشتیبانی را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "SUPPORT_TEXT"
            return
        if text == "⏰ زمان لغو سفارش":
            current = config.get("CANCEL_TIME_MINUTES", 20)
            await update.message.reply_text(f"⏰ زمان فعلی: {current} دقیقه\n\nزمان جدید لغو سفارش (به دقیقه) را وارد کنید:", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "CANCEL_TIME_MINUTES"
            return
        if text == "🔄 بازه چک سفارش‌ها":
            current = config.get("CHECK_INTERVAL_SECONDS", 60)
            await update.message.reply_text(f"🔄 بازه فعلی: {current} ثانیه\n\nبازه جدید چک سفارش‌ها (به ثانیه) را وارد کنید:\n💡 پیشنهاد: بین 30 تا 120 ثانیه", reply_markup=input_cancel_menu())
            context.user_data["setting"] = "CHECK_INTERVAL_SECONDS"
            return

        if "setting" in context.user_data:
            key = context.user_data["setting"]
            value = text
            if key in ["PRODUCT_PRICE", "CANCEL_TIME_MINUTES", "CHECK_INTERVAL_SECONDS"]:
                try:
                    value = int(value)
                    if value <= 0:
                        raise ValueError()
                    if key == "CHECK_INTERVAL_SECONDS" and value < 10:
                        await update.message.reply_text("❌ بازه چک نباید کمتر از 10 ثانیه باشد.", reply_markup=settings_menu())
                        context.user_data.clear()
                        context.user_data["mode"] = "settings"
                        return
                except ValueError:
                    await update.message.reply_text("❌ لطفاً مقدار عددی معتبر وارد کنید.", reply_markup=settings_menu())
                    context.user_data.clear()
                    context.user_data["mode"] = "settings"
                    return
            config[key] = value
            save_config()
            key_names = {"PRODUCT_NAME": "نام محصول", "PRODUCT_PRICE": "قیمت محصول", "CARD_NUMBER": "شماره کارت",
                        "ABOUT_TEXT": "درباره محصول", "RULES_TEXT": "قوانین", "SUPPORT_TEXT": "پشتیبانی",
                        "CANCEL_TIME_MINUTES": "زمان لغو سفارش", "CHECK_INTERVAL_SECONDS": "بازه چک سفارش‌ها"}
            key_name = key_names.get(key, key)
            context.user_data.clear()
            await update.message.reply_text(f"✅ {key_name} با موفقیت ذخیره شد.", reply_markup=settings_menu())
            context.user_data["mode"] = "settings"
            return

    if text == "✅ تایید پرداخت":
        await update.message.reply_text("🔢 شماره سفارش را برای تایید پرداخت وارد کنید:", reply_markup=input_cancel_menu())
        context.user_data["mode"] = "confirm_payment"
        return

    if context.user_data.get("mode") == "confirm_payment":
        try:
            order_id = int(text)
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT user_id, status FROM orders WHERE id=?", (order_id,))
            row = c.fetchone()
            if not row:
                await update.message.reply_text("❌ سفارش یافت نشد.", reply_markup=admin_menu())
                context.user_data.clear()
                conn.close()
                return
            user_id, status = row
            if status == "paid":
                await update.message.reply_text("⚠️ این سفارش قبلاً تایید شده است.", reply_markup=admin_menu())
                context.user_data.clear()
                conn.close()
                return
            if status == "cancelled":
                await update.message.reply_text("⚠️ این سفارش لغو شده است.", reply_markup=admin_menu())
                context.user_data.clear()
                conn.close()
                return
            c.execute("UPDATE orders SET status='paid' WHERE id=?", (order_id,))
            conn.commit()
            conn.close()
            try:
                await context.bot.send_message(user_id, f"✅ پرداخت سفارش #{order_id} تایید شد.\n⏳ اکانت شما به زودی ارسال خواهد شد.")
            except Exception as e:
                logger.error(f"Error notifying user: {e}")
            await update.message.reply_text(f"✅ پرداخت سفارش #{order_id} تایید شد.", reply_markup=admin_menu())
            context.user_data.clear()
            return
        except ValueError:
            await update.message.reply_text("❌ لطفاً شماره سفارش معتبر وارد کنید.", reply_markup=admin_menu())
            context.user_data.clear()
            return

    if text == "📤 ارسال اکانت":
        await update.message.reply_text("🔢 شماره سفارش را برای ارسال اکانت وارد کنید:", reply_markup=input_cancel_menu())
        context.user_data["mode"] = "send_account_order"
        return

    if context.user_data.get("mode") == "send_account_order":
        try:
            order_id = int(text)
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT user_id, status FROM orders WHERE id=?", (order_id,))
            row = c.fetchone()
            conn.close()
            if not row:
                await update.message.reply_text("❌ سفارش یافت نشد.", reply_markup=admin_menu())
                context.user_data.clear()
                return
            user_id, status = row
            if status != "paid":
                await update.message.reply_text("⚠️ این سفارش هنوز پرداخت نشده است.", reply_markup=admin_menu())
                context.user_data.clear()
                return
            context.user_data["mode"] = "send_account_data"
            context.user_data["order_id"] = order_id
            context.user_data["user_id"] = user_id
            await update.message.reply_text("📧 اکانت را به فرمت email | password ارسال کنید:", reply_markup=input_cancel_menu())
            return
        except ValueError:
            await update.message.reply_text("❌ لطفاً شماره سفارش معتبر وارد کنید.", reply_markup=admin_menu())
            context.user_data.clear()
            return

    if context.user_data.get("mode") == "send_account_data":
        account_data = text
        order_id = context.user_data.get("order_id")
        user_id = context.user_data.get("user_id")
        try:
            await context.bot.send_message(user_id, f"🎉 اکانت سفارش #{order_id} شما:\n\n📧 {account_data}\n\n✅ از خرید شما متشکریم!")
        except Exception as e:
            await update.message.reply_text(f"❌ خطا در ارسال به کاربر: {e}", reply_markup=admin_menu())
            context.user_data.clear()
            return
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("UPDATE orders SET status='delivered' WHERE id=?", (order_id,))
        conn.commit()
        conn.close()
        await update.message.reply_text(f"✅ اکانت سفارش #{order_id} ارسال شد.", reply_markup=admin_menu())
        context.user_data.clear()
        return

    if text == "📋 سفارش‌های در انتظار":
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("SELECT id, username, price, created_at, receipt, discount_code FROM orders WHERE status='pending'")
        rows = c.fetchall()
        conn.close()
        if not rows:
            await update.message.reply_text("📭 هیچ سفارش در انتظاری وجود ندارد.", reply_markup=admin_menu())
            return
        msg = "📋 سفارش‌های در انتظار:\n"
        for r in rows:
            receipt_status = "✅ رسید" if r[4] else "⏳ بدون رسید"
            discount_text = f" | 🎟️{r[5]}" if r[5] else ""
            msg += f"#{r[0]} | @{r[1]} | {r[2]:,}ت{discount_text} | {r[3][:16]} | {receipt_status}\n"
        await update.message.reply_text(msg, reply_markup=admin_menu())
        return

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    text = update.message.text
    if user.id == ADMIN_CHAT_ID:
        return
    if text == "❌ انصراف و بازگشت":
        context.user_data.clear()
        await update.message.reply_text("🔙 به منوی اصلی بازگشتید.", reply_markup=main_menu())
        return
    if await handle_discount_code_input(update, context):
        return
    if "waiting_receipt" in context.user_data:
        await handle_receipt(update, context)
        return

def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()
    job_queue = app.job_queue
    check_interval = config.get("CHECK_INTERVAL_SECONDS", 60)
    job_queue.run_repeating(cancel_expired_orders, interval=check_interval, first=10)
    logger.info(f"Check interval: {check_interval}s")

    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.Regex("^🛒 خرید اکانت$"), buy_start))
    app.add_handler(MessageHandler(filters.Regex("^🎟️ دارم کد تخفیف$"), buy_with_discount))
    app.add_handler(MessageHandler(filters.Regex("^❌ بدون کد تخفیف$"), buy_without_discount))
    app.add_handler(MessageHandler(filters.Regex("^📤 ارسال رسید پرداخت$"), handle_receipt_request))
    app.add_handler(MessageHandler(filters.Regex("^🔙 بازگشت به منوی اصلی$"), back))
    app.add_handler(MessageHandler(filters.PHOTO & ~filters.User(ADMIN_CHAT_ID), handle_receipt))
    app.add_handler(MessageHandler(filters.Regex("^📦 سفارش‌های من$"), my_orders))
    app.add_handler(MessageHandler(filters.Regex("^ℹ️ درباره محصول$"), about))
    app.add_handler(MessageHandler(filters.Regex("^📜 قوانین$"), rules))
    app.add_handler(MessageHandler(filters.Regex("^📞 پشتیبانی$"), support))
    app.add_handler(CommandHandler("admin", admin))
    app.add_handler(MessageHandler(filters.User(ADMIN_CHAT_ID) & filters.TEXT, admin_action))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.User(ADMIN_CHAT_ID) & ~filters.COMMAND, handle_text))

    logger.info("🤖 Bot started")
    app.run_polling()

if __name__ == "__main__":
    main()
PYEOF

cat > Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir "python-telegram-bot[job-queue]"==20.7

COPY bot.py .

RUN mkdir -p /app/data

CMD ["python", "bot.py"]
DOCKERFILE

cat > docker-compose.yml << 'COMPOSE'
version: '3.8'

services:
  bot:
    build: .
    container_name: chatgpt-seller-bot
    restart: unless-stopped
    environment:
      - BOT_TOKEN=${BOT_TOKEN}
      - ADMIN_ID=${ADMIN_ID}
    volumes:
      - ./data:/app/data
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE

echo "✅ فایل‌های پروژه ساخته شدند."

mkdir -p data

if [ ! -f .env ]; then
    echo ""
    echo "⚙️ تنظیم اولیه ربات:"
    read -p "توکن ربات تلگرام: " BOT_TOKEN
    read -p "آیدی عددی ادمین: " ADMIN_ID
    
    cat > .env << EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_ID=$ADMIN_ID
EOF
    echo "✅ فایل .env ساخته شد."
fi

echo ""
echo "🐳 ساخت و اجرای کانتینر Docker ..."

docker compose down 2>/dev/null || true
docker compose up -d --build

echo ""
echo "✅ ربات با موفقیت اجرا شد!"
echo ""
echo "📋 دستورات مفید:"
echo "   مشاهده لاگ:     docker compose logs -f"
echo "   توقف ربات:      docker compose down"
echo "   ریستارت:        docker compose restart"
echo "   وضعیت:          docker compose ps"
echo ""
