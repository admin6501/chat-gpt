#!/bin/bash
set -e

BOT_DIR="chatgpt-seller-bot"
BACKUP_DIR="backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}    ${GREEN}🤖 مدیریت ربات فروش ChatGPT${NC}            ${BLUE}║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}1)${NC} 📦 نصب / نصب مجدد ربات                  ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}2)${NC} 🔄 آپدیت ربات (بدون حذف دیتا)           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}3)${NC} ▶️  استارت ربات                          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}4)${NC} 🔁 ری‌استارت ربات                        ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}5)${NC} ⏹️  استاپ ربات                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}6)${NC} 💾 بکاپ گرفتن                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}7)${NC} 📥 بازیابی بکاپ                         ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}8)${NC} 📋 مشاهده لاگ                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}9)${NC} 📊 وضعیت ربات                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}10)${NC} 🗑️  حذف کامل ربات                       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}0)${NC} 🚪 خروج                                 ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}📦 در حال نصب Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        sudo systemctl start docker
        sudo systemctl enable docker
        echo -e "${GREEN}✅ Docker نصب شد.${NC}"
    else
        echo -e "${GREEN}✅ Docker از قبل نصب است.${NC}"
    fi
}

create_bot_files() {
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
    c.execute("""CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER, username TEXT, fullname TEXT, price INTEGER,
        original_price INTEGER, discount_code TEXT, discount_amount INTEGER DEFAULT 0,
        status TEXT, created_at TEXT, receipt TEXT)""")
    c.execute("""CREATE TABLE IF NOT EXISTS discount_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE, discount_type TEXT, discount_value INTEGER,
        max_usage_total INTEGER DEFAULT 0, max_usage_per_user INTEGER DEFAULT 0,
        expires_at TEXT, is_active INTEGER DEFAULT 1, created_at TEXT)""")
    c.execute("""CREATE TABLE IF NOT EXISTS discount_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT, user_id INTEGER, order_id INTEGER, used_at TEXT)""")
    conn.commit()
    conn.close()

def main_menu(is_admin=False):
    keys = [["🛒 خرید اکانت", "📦 سفارش‌های من"],["ℹ️ درباره محصول", "📜 قوانین"],["📞 پشتیبانی"]]
    if is_admin:
        keys.append(["👑 پنل مدیریت"])
    return ReplyKeyboardMarkup(keys, resize_keyboard=True)

def after_order_menu():
    return ReplyKeyboardMarkup([["📤 ارسال رسید پرداخت"], ["🔙 بازگشت به منوی اصلی"]], resize_keyboard=True)

def buy_menu():
    return ReplyKeyboardMarkup([["🎟️ دارم کد تخفیف", "❌ بدون کد تخفیف"],["🔙 بازگشت به منوی اصلی"]], resize_keyboard=True)

def admin_menu():
    return ReplyKeyboardMarkup([["📋 سفارش‌های در انتظار", "✅ تایید پرداخت"],["📤 ارسال اکانت", "⚙️ تنظیمات فروشگاه"],["بازگشت به منوی اصلی"]], resize_keyboard=True)

def settings_menu():
    return ReplyKeyboardMarkup([
        ["🛒 نام محصول", "💰 قیمت محصول"],
        ["💳 شماره کارت", "ℹ️ درباره محصول"],
        ["📜 قوانین", "📞 پشتیبانی"],
        ["⏰ زمان لغو سفارش", "🔄 بازه چک سفارش‌ها"],
        ["🎟️ مدیریت کدهای تخفیف"],
        ["🔙 بازگشت به پنل ادمین", "🏠 منوی اصلی"]
    ], resize_keyboard=True)

def discount_menu():
    return ReplyKeyboardMarkup([
        ["➕ افزودن کد تخفیف"],
        ["📋 لیست کدها", "📊 آمار کد"],
        ["❌ غیرفعال کردن", "🗑️ حذف کد"],
        ["🔙 بازگشت به تنظیمات"]
    ], resize_keyboard=True)

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
        if datetime.now(IRAN_TZ) > datetime.fromisoformat(expires_at):
            conn.close()
            return None, "❌ کد تخفیف منقضی شده است."
    if max_total > 0:
        c.execute("SELECT COUNT(*) FROM discount_usage WHERE code=?", (code.upper(),))
        if c.fetchone()[0] >= max_total:
            conn.close()
            return None, "❌ ظرفیت استفاده از این کد تکمیل شده است."
    if max_per_user > 0:
        c.execute("SELECT COUNT(*) FROM discount_usage WHERE code=? AND user_id=?", (code.upper(), user_id))
        if c.fetchone()[0] >= max_per_user:
            conn.close()
            return None, "❌ شما قبلاً از این کد تخفیف استفاده کرده‌اید."
    conn.close()
    return {"code": code_text, "type": discount_type, "value": discount_value}, None

def calculate_discounted_price(original_price, discount_info):
    if discount_info["type"] == "percent":
        discount_amount = int(original_price * discount_info["value"] / 100)
    else:
        discount_amount = discount_info["value"]
    return max(0, original_price - discount_amount), discount_amount

def record_discount_usage(code, user_id, order_id):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("INSERT INTO discount_usage (code, user_id, order_id, used_at) VALUES (?,?,?,?)",
              (code.upper(), user_id, order_id, datetime.now(IRAN_TZ).isoformat()))
    conn.commit()
    conn.close()

async def cancel_expired_orders(context: ContextTypes.DEFAULT_TYPE):
    cancel_minutes = config.get("CANCEL_TIME_MINUTES", 20)
    cutoff_time = datetime.now(IRAN_TZ) - timedelta(minutes=cancel_minutes)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT id, user_id, fullname FROM orders WHERE status='pending' AND receipt IS NULL AND created_at < ?", (cutoff_time.isoformat(),))
    for order_id, user_id, fullname in c.fetchall():
        c.execute("UPDATE orders SET status='cancelled' WHERE id=?", (order_id,))
        try: await context.bot.send_message(user_id, f"⛔ سفارش #{order_id} لغو شد (عدم پرداخت در {cancel_minutes} دقیقه)")
        except: pass
        try: await context.bot.send_message(ADMIN_CHAT_ID, f"🔴 سفارش #{order_id} ({fullname}) لغو شد")
        except: pass
    conn.commit()
    conn.close()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    is_admin = update.effective_user.id == ADMIN_CHAT_ID
    await update.message.reply_text(f"👋 خوش آمدید!\n🛍️ {config['PRODUCT_NAME']}\n💰 قیمت: {config['PRODUCT_PRICE']:,} تومان", reply_markup=main_menu(is_admin))

async def buy_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["buying"] = True
    await update.message.reply_text(f"🛒 خرید {config['PRODUCT_NAME']}\n💰 قیمت: {config['PRODUCT_PRICE']:,} تومان\n\n🎟️ آیا کد تخفیف دارید؟", reply_markup=buy_menu())

async def buy_with_discount(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.user_data.get("buying"):
        is_admin = update.effective_user.id == ADMIN_CHAT_ID
        await update.message.reply_text("لطفاً ابتدا روی خرید اکانت کلیک کنید.", reply_markup=main_menu(is_admin))
        return
    context.user_data["waiting_discount_code"] = True
    await update.message.reply_text("🎟️ کد تخفیف را وارد کنید:", reply_markup=user_input_cancel_menu())

async def buy_without_discount(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.user_data.get("buying"):
        is_admin = update.effective_user.id == ADMIN_CHAT_ID
        await update.message.reply_text("لطفاً ابتدا روی خرید اکانت کلیک کنید.", reply_markup=main_menu(is_admin))
        return
    await process_order(update, context, None)

async def process_order(update: Update, context: ContextTypes.DEFAULT_TYPE, discount_info):
    user = update.effective_user
    original_price = config['PRODUCT_PRICE']
    if discount_info:
        final_price, discount_amount = calculate_discounted_price(original_price, discount_info)
        discount_code = discount_info["code"]
    else:
        final_price, discount_amount, discount_code = original_price, 0, None
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("INSERT INTO orders (user_id,username,fullname,price,original_price,discount_code,discount_amount,status,created_at) VALUES (?,?,?,?,?,?,?,?,?)",
              (user.id, user.username, user.full_name, final_price, original_price, discount_code, discount_amount, "pending", datetime.now(IRAN_TZ).isoformat()))
    conn.commit()
    oid = c.lastrowid
    conn.close()
    if discount_code: record_discount_usage(discount_code, user.id, oid)
    admin_msg = f"🆕 سفارش جدید:\n👤 {user.full_name} (@{user.username})\n🆔 #{oid}\n"
    if discount_code: admin_msg += f"🎟️ کد: {discount_code}\n💰 اصلی: {original_price:,}\n💸 تخفیف: {discount_amount:,}\n"
    admin_msg += f"💵 نهایی: {final_price:,} تومان"
    await context.bot.send_message(ADMIN_CHAT_ID, admin_msg)
    user_msg = f"✅ سفارش #{oid} ثبت شد.\n"
    if discount_code: user_msg += f"🎟️ کد: {discount_code}\n💰 اصلی: {original_price:,}\n💸 تخفیف: {discount_amount:,}\n"
    user_msg += f"💵 مبلغ: {final_price:,} تومان\n\n💳 شماره کارت:\n{config['CARD_NUMBER']}\n\n⏰ مهلت پرداخت: {config['CANCEL_TIME_MINUTES']} دقیقه"
    await update.message.reply_text(user_msg, reply_markup=after_order_menu())
    context.user_data.clear()
    context.user_data["current_order"] = oid

async def handle_discount_code_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.user_data.get("waiting_discount_code"): return False
    code = update.message.text.strip()
    if code == "❌ انصراف و بازگشت":
        context.user_data.clear()
        is_admin = update.effective_user.id == ADMIN_CHAT_ID
        await update.message.reply_text("🔙 منوی اصلی", reply_markup=main_menu(is_admin))
        return True
    discount_info, error = validate_discount_code(code, update.effective_user.id)
    if error:
        await update.message.reply_text(error, reply_markup=buy_menu())
        context.user_data["waiting_discount_code"] = False
        return True
    original_price = config['PRODUCT_PRICE']
    final_price, discount_amount = calculate_discounted_price(original_price, discount_info)
    dtype = f"{discount_info['value']}%" if discount_info["type"] == "percent" else f"{discount_info['value']:,}ت"
    await update.message.reply_text(f"✅ کد معتبر!\n🎟️ {discount_info['code']}\n💯 تخفیف: {dtype}\n💵 نهایی: {final_price:,}\n\nدر حال ثبت...")
    context.user_data["waiting_discount_code"] = False
    await process_order(update, context, discount_info)
    return True

async def back(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data.clear()
    is_admin = update.effective_user.id == ADMIN_CHAT_ID
    await update.message.reply_text("🔙 منوی اصلی", reply_markup=main_menu(is_admin))

async def handle_receipt_request(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if "current_order" not in context.user_data:
        is_admin = update.effective_user.id == ADMIN_CHAT_ID
        await update.message.reply_text("⛔ سفارشی در انتظار نیست.", reply_markup=main_menu(is_admin))
        return
    oid = context.user_data["current_order"]
    await update.message.reply_text(f"📸 رسید سفارش #{oid} را ارسال کنید:", reply_markup=user_input_cancel_menu())
    context.user_data["waiting_receipt"] = oid

async def handle_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if "waiting_receipt" not in context.user_data: return
    user = update.effective_user
    oid = context.user_data["waiting_receipt"]
    caption = f"📩 رسید سفارش #{oid}\n👤 {user.full_name} (@{user.username})"
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("UPDATE orders SET receipt=? WHERE id=?", ("sent", oid))
    conn.commit()
    conn.close()
    if update.message.photo:
        await context.bot.send_photo(ADMIN_CHAT_ID, photo=update.message.photo[-1].file_id, caption=caption)
    else:
        await context.bot.send_message(ADMIN_CHAT_ID, text=f"{caption}\n📝 {update.message.text}")
    is_admin = update.effective_user.id == ADMIN_CHAT_ID
    await update.message.reply_text("✅ رسید ارسال شد.", reply_markup=main_menu(is_admin))
    context.user_data.clear()

async def my_orders(update: Update, context: ContextTypes.DEFAULT_TYPE):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT id, status, price, discount_code, discount_amount FROM orders WHERE user_id=?", (update.effective_user.id,))
    rows = c.fetchall()
    conn.close()
    is_admin = update.effective_user.id == ADMIN_CHAT_ID
    if not rows:
        await update.message.reply_text("📭 سفارشی ندارید.", reply_markup=main_menu(is_admin))
        return
    status_map = {"pending": "⏳در انتظار", "paid": "✅پرداخت شده", "delivered": "📦تحویل شده", "cancelled": "❌لغو شده"}
    msg = "📦 سفارش‌های شما:\n\n"
    for r in rows:
        disc = f" (تخفیف:{r[4]:,})" if r[3] else ""
        msg += f"#{r[0]} | {r[2]:,}ت{disc} | {status_map.get(r[1],r[1])}\n"
    await update.message.reply_text(msg, reply_markup=main_menu(is_admin))

async def about(update: Update, context: ContextTypes.DEFAULT_TYPE):
    is_admin = update.effective_user.id == ADMIN_CHAT_ID
    await update.message.reply_text(config["ABOUT_TEXT"], reply_markup=main_menu(is_admin))

async def rules(update: Update, context: ContextTypes.DEFAULT_TYPE):
    is_admin = update.effective_user.id == ADMIN_CHAT_ID
    await update.message.reply_text(config["RULES_TEXT"], reply_markup=main_menu(is_admin))

async def support(update: Update, context: ContextTypes.DEFAULT_TYPE):
    is_admin = update.effective_user.id == ADMIN_CHAT_ID
    await update.message.reply_text(config["SUPPORT_TEXT"], reply_markup=main_menu(is_admin))

async def admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID:
        await update.message.reply_text("⛔ دسترسی ندارید.")
        return
    await update.message.reply_text("👑 پنل ادمین", reply_markup=admin_menu())

async def admin_action(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_CHAT_ID: return
    text = update.message.text

    if text == "بازگشت به منوی اصلی":
        context.user_data.clear()
        await update.message.reply_text("🔙 منوی اصلی", reply_markup=main_menu(True))
        return
    if text == "🏠 منوی اصلی":
        context.user_data.clear()
        await update.message.reply_text("🔙 منوی اصلی", reply_markup=main_menu(True))
        return
    if text == "👑 پنل مدیریت":
        context.user_data.clear()
        await update.message.reply_text("👑 پنل ادمین", reply_markup=admin_menu())
        return
    if text == "❌ انصراف":
        mode = context.user_data.get("mode")
        context.user_data.clear()
        if mode == "settings":
            context.user_data["mode"] = "settings"
            await update.message.reply_text("لغو شد.", reply_markup=settings_menu())
        elif mode == "discount":
            context.user_data["mode"] = "discount"
            await update.message.reply_text("لغو شد.", reply_markup=discount_menu())
        else:
            await update.message.reply_text("لغو شد.", reply_markup=admin_menu())
        return

    if text == "⚙️ تنظیمات فروشگاه":
        context.user_data["mode"] = "settings"
        await update.message.reply_text("⚙️ تنظیمات فروشگاه:", reply_markup=settings_menu())
        return

    if context.user_data.get("mode") == "settings":
        if text == "🔙 بازگشت به پنل ادمین":
            context.user_data.clear()
            await update.message.reply_text("👑 پنل ادمین", reply_markup=admin_menu())
            return
        
        if text == "🎟️ مدیریت کدهای تخفیف":
            context.user_data["mode"] = "discount"
            await update.message.reply_text("🎟️ مدیریت کدهای تخفیف:", reply_markup=discount_menu())
            return

        settings_map = {
            "🛒 نام محصول": ("PRODUCT_NAME", "نام محصول را وارد کنید:"),
            "💰 قیمت محصول": ("PRODUCT_PRICE", "قیمت محصول (تومان) را وارد کنید:"),
            "💳 شماره کارت": ("CARD_NUMBER", "شماره کارت را وارد کنید:"),
            "ℹ️ درباره محصول": ("ABOUT_TEXT", "متن درباره محصول را وارد کنید:"),
            "📜 قوانین": ("RULES_TEXT", "متن قوانین را وارد کنید:"),
            "📞 پشتیبانی": ("SUPPORT_TEXT", "متن پشتیبانی را وارد کنید:"),
            "⏰ زمان لغو سفارش": ("CANCEL_TIME_MINUTES", "زمان لغو سفارش (دقیقه) را وارد کنید:"),
            "🔄 بازه چک سفارش‌ها": ("CHECK_INTERVAL_SECONDS", "بازه چک سفارش‌ها (ثانیه) را وارد کنید:\n(حداقل 10 ثانیه)")
        }
        if text in settings_map:
            key, prompt = settings_map[text]
            context.user_data["setting"] = key
            cur = config.get(key, "")
            await update.message.reply_text(f"مقدار فعلی: {cur}\n\n{prompt}", reply_markup=input_cancel_menu())
            return

        if "setting" in context.user_data:
            key = context.user_data["setting"]
            val = text
            if key in ["PRODUCT_PRICE", "CANCEL_TIME_MINUTES", "CHECK_INTERVAL_SECONDS"]:
                try:
                    val = int(val)
                    if val <= 0: raise ValueError()
                    if key == "CHECK_INTERVAL_SECONDS" and val < 10:
                        await update.message.reply_text("❌ حداقل 10 ثانیه", reply_markup=settings_menu())
                        context.user_data.pop("setting", None)
                        return
                except:
                    await update.message.reply_text("❌ عدد نامعتبر", reply_markup=settings_menu())
                    context.user_data.pop("setting", None)
                    return
            config[key] = val
            save_config()
            context.user_data.pop("setting", None)
            await update.message.reply_text("✅ ذخیره شد.", reply_markup=settings_menu())
            return

    if context.user_data.get("mode") == "discount":
        if text == "🔙 بازگشت به تنظیمات":
            context.user_data.clear()
            context.user_data["mode"] = "settings"
            await update.message.reply_text("⚙️ تنظیمات فروشگاه:", reply_markup=settings_menu())
            return

        if text == "➕ افزودن کد تخفیف":
            context.user_data["add_discount"] = {}
            context.user_data["add_step"] = "code"
            await update.message.reply_text("🎟️ مرحله 1 از 6\n\n📝 کد تخفیف را وارد کنید:\n(مثال: SALE20)", reply_markup=input_cancel_menu())
            return

        if text == "📋 لیست کدها":
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT code, discount_type, discount_value, max_usage_total, max_usage_per_user, expires_at, is_active FROM discount_codes ORDER BY id DESC")
            codes = c.fetchall()
            conn.close()
            if not codes:
                await update.message.reply_text("📭 کدی وجود ندارد.", reply_markup=discount_menu())
                return
            msg = "📋 کدهای تخفیف:\n\n"
            for cd in codes:
                t = f"{cd[2]}%" if cd[1] == "percent" else f"{cd[2]:,}ت"
                s = "✅" if cd[6] else "❌"
                e = cd[5][:10] if cd[5] else "∞"
                msg += f"{s} {cd[0]} | {t} | کل:{cd[3] or '∞'} | کاربر:{cd[4] or '∞'} | انقضا:{e}\n"
            await update.message.reply_text(msg, reply_markup=discount_menu())
            return

        if text == "📊 آمار کد":
            context.user_data["discount_action"] = "stats"
            await update.message.reply_text("🎟️ کد تخفیف را وارد کنید:", reply_markup=input_cancel_menu())
            return

        if text == "❌ غیرفعال کردن":
            context.user_data["discount_action"] = "deactivate"
            await update.message.reply_text("🎟️ کد تخفیف را وارد کنید:", reply_markup=input_cancel_menu())
            return

        if text == "🗑️ حذف کد":
            context.user_data["discount_action"] = "delete"
            await update.message.reply_text("🎟️ کد تخفیف را برای حذف وارد کنید:", reply_markup=input_cancel_menu())
            return

        # مراحل افزودن کد تخفیف
        if "add_step" in context.user_data:
            step = context.user_data["add_step"]
            data = context.user_data.get("add_discount", {})

            if step == "code":
                data["code"] = text.upper().strip()
                context.user_data["add_discount"] = data
                context.user_data["add_step"] = "type"
                await update.message.reply_text("🎟️ مرحله 2 از 6\n\n📊 نوع تخفیف را انتخاب کنید:\n\n1️⃣ درصدی (مثلاً 20%)\n2️⃣ مبلغی (مثلاً 50000 تومان)\n\nعدد 1 یا 2 را وارد کنید:", reply_markup=input_cancel_menu())
                return

            if step == "type":
                if text == "1":
                    data["type"] = "percent"
                    context.user_data["add_discount"] = data
                    context.user_data["add_step"] = "value"
                    await update.message.reply_text("🎟️ مرحله 3 از 6\n\n💯 درصد تخفیف را وارد کنید:\n(عددی بین 1 تا 100)", reply_markup=input_cancel_menu())
                elif text == "2":
                    data["type"] = "amount"
                    context.user_data["add_discount"] = data
                    context.user_data["add_step"] = "value"
                    await update.message.reply_text("🎟️ مرحله 3 از 6\n\n💰 مبلغ تخفیف (تومان) را وارد کنید:", reply_markup=input_cancel_menu())
                else:
                    await update.message.reply_text("❌ لطفاً 1 یا 2 وارد کنید:", reply_markup=input_cancel_menu())
                return

            if step == "value":
                try:
                    val = int(text)
                    if data["type"] == "percent" and (val < 1 or val > 100):
                        await update.message.reply_text("❌ درصد باید بین 1 تا 100 باشد:", reply_markup=input_cancel_menu())
                        return
                    if val <= 0:
                        await update.message.reply_text("❌ مقدار باید بزرگتر از صفر باشد:", reply_markup=input_cancel_menu())
                        return
                    data["value"] = val
                    context.user_data["add_discount"] = data
                    context.user_data["add_step"] = "max_total"
                    await update.message.reply_text("🎟️ مرحله 4 از 6\n\n📊 حداکثر تعداد استفاده کلی را وارد کنید:\n(0 = نامحدود)", reply_markup=input_cancel_menu())
                except:
                    await update.message.reply_text("❌ عدد نامعتبر:", reply_markup=input_cancel_menu())
                return

            if step == "max_total":
                try:
                    val = int(text)
                    if val < 0: raise ValueError()
                    data["max_total"] = val
                    context.user_data["add_discount"] = data
                    context.user_data["add_step"] = "max_per_user"
                    await update.message.reply_text("🎟️ مرحله 5 از 6\n\n👤 حداکثر استفاده برای هر کاربر را وارد کنید:\n(0 = نامحدود)", reply_markup=input_cancel_menu())
                except:
                    await update.message.reply_text("❌ عدد نامعتبر:", reply_markup=input_cancel_menu())
                return

            if step == "max_per_user":
                try:
                    val = int(text)
                    if val < 0: raise ValueError()
                    data["max_per_user"] = val
                    context.user_data["add_discount"] = data
                    context.user_data["add_step"] = "expire_days"
                    await update.message.reply_text("🎟️ مرحله 6 از 6\n\n📅 تعداد روز تا انقضا را وارد کنید:\n(0 = بدون انقضا)", reply_markup=input_cancel_menu())
                except:
                    await update.message.reply_text("❌ عدد نامعتبر:", reply_markup=input_cancel_menu())
                return

            if step == "expire_days":
                try:
                    days = int(text)
                    if days < 0: raise ValueError()
                    expires_at = (datetime.now(IRAN_TZ) + timedelta(days=days)).isoformat() if days > 0 else None
                    conn = sqlite3.connect(DB_FILE)
                    c = conn.cursor()
                    c.execute("INSERT INTO discount_codes (code,discount_type,discount_value,max_usage_total,max_usage_per_user,expires_at,created_at) VALUES (?,?,?,?,?,?,?)",
                              (data["code"], data["type"], data["value"], data["max_total"], data["max_per_user"], expires_at, datetime.now(IRAN_TZ).isoformat()))
                    conn.commit()
                    conn.close()
                    
                    t = f"{data['value']}%" if data["type"] == "percent" else f"{data['value']:,} تومان"
                    mt = str(data['max_total']) if data['max_total'] > 0 else "نامحدود"
                    mu = str(data['max_per_user']) if data['max_per_user'] > 0 else "نامحدود"
                    exp = f"{days} روز" if days > 0 else "بدون انقضا"
                    
                    await update.message.reply_text(f"✅ کد تخفیف ایجاد شد!\n\n🎟️ کد: {data['code']}\n💯 تخفیف: {t}\n📊 حداکثر کل: {mt}\n👤 حداکثر هر کاربر: {mu}\n📅 اعتبار: {exp}", reply_markup=discount_menu())
                    context.user_data.pop("add_discount", None)
                    context.user_data.pop("add_step", None)
                except sqlite3.IntegrityError:
                    await update.message.reply_text("❌ این کد قبلاً وجود دارد.", reply_markup=discount_menu())
                    context.user_data.pop("add_discount", None)
                    context.user_data.pop("add_step", None)
                except:
                    await update.message.reply_text("❌ عدد نامعتبر:", reply_markup=input_cancel_menu())
                return

        if context.user_data.get("discount_action") == "stats":
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT discount_type, discount_value, max_usage_total FROM discount_codes WHERE code=?", (text.upper(),))
            info = c.fetchone()
            if not info:
                await update.message.reply_text("❌ کد یافت نشد.", reply_markup=discount_menu())
            else:
                c.execute("SELECT COUNT(*) FROM discount_usage WHERE code=?", (text.upper(),))
                used = c.fetchone()[0]
                c.execute("SELECT SUM(discount_amount) FROM orders WHERE discount_code=?", (text.upper(),))
                total = c.fetchone()[0] or 0
                t = f"{info[1]}%" if info[0] == "percent" else f"{info[1]:,}ت"
                await update.message.reply_text(f"📊 آمار {text.upper()}:\n\nتخفیف: {t}\nاستفاده: {used}/{info[2] or '∞'}\nمجموع تخفیف: {total:,}ت", reply_markup=discount_menu())
            conn.close()
            context.user_data.pop("discount_action", None)
            return

        if context.user_data.get("discount_action") == "deactivate":
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("UPDATE discount_codes SET is_active=0 WHERE code=?", (text.upper(),))
            await update.message.reply_text("✅ غیرفعال شد." if c.rowcount else "❌ یافت نشد.", reply_markup=discount_menu())
            conn.commit()
            conn.close()
            context.user_data.pop("discount_action", None)
            return

        if context.user_data.get("discount_action") == "delete":
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("DELETE FROM discount_usage WHERE code=?", (text.upper(),))
            c.execute("DELETE FROM discount_codes WHERE code=?", (text.upper(),))
            await update.message.reply_text("🗑️ حذف شد." if c.rowcount else "❌ یافت نشد.", reply_markup=discount_menu())
            conn.commit()
            conn.close()
            context.user_data.pop("discount_action", None)
            return

    if text == "✅ تایید پرداخت":
        context.user_data["mode"] = "confirm"
        await update.message.reply_text("شماره سفارش:", reply_markup=input_cancel_menu())
        return

    if context.user_data.get("mode") == "confirm":
        try:
            oid = int(text)
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT user_id, status FROM orders WHERE id=?", (oid,))
            row = c.fetchone()
            if not row:
                await update.message.reply_text("❌ یافت نشد.", reply_markup=admin_menu())
            elif row[1] != "pending":
                await update.message.reply_text(f"⚠️ وضعیت: {row[1]}", reply_markup=admin_menu())
            else:
                c.execute("UPDATE orders SET status='paid' WHERE id=?", (oid,))
                conn.commit()
                try: await context.bot.send_message(row[0], f"✅ سفارش #{oid} تایید شد.")
                except: pass
                await update.message.reply_text(f"✅ سفارش #{oid} تایید شد.", reply_markup=admin_menu())
            conn.close()
        except:
            await update.message.reply_text("❌ شماره نامعتبر.", reply_markup=admin_menu())
        context.user_data.clear()
        return

    if text == "📤 ارسال اکانت":
        context.user_data["mode"] = "send"
        await update.message.reply_text("شماره سفارش:", reply_markup=input_cancel_menu())
        return

    if context.user_data.get("mode") == "send":
        try:
            oid = int(text)
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT user_id, status FROM orders WHERE id=?", (oid,))
            row = c.fetchone()
            conn.close()
            if not row:
                await update.message.reply_text("❌ یافت نشد.", reply_markup=admin_menu())
                context.user_data.clear()
            elif row[1] != "paid":
                await update.message.reply_text("⚠️ پرداخت نشده.", reply_markup=admin_menu())
                context.user_data.clear()
            else:
                context.user_data["mode"] = "send_data"
                context.user_data["order_id"] = oid
                context.user_data["user_id"] = row[0]
                await update.message.reply_text("📧 اکانت (email|pass):", reply_markup=input_cancel_menu())
        except:
            await update.message.reply_text("❌ شماره نامعتبر.", reply_markup=admin_menu())
            context.user_data.clear()
        return

    if context.user_data.get("mode") == "send_data":
        oid, uid = context.user_data["order_id"], context.user_data["user_id"]
        try:
            await context.bot.send_message(uid, f"🎉 اکانت سفارش #{oid}:\n\n📧 {text}\n\n✅ متشکریم!")
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("UPDATE orders SET status='delivered' WHERE id=?", (oid,))
            conn.commit()
            conn.close()
            await update.message.reply_text("✅ ارسال شد.", reply_markup=admin_menu())
        except Exception as e:
            await update.message.reply_text(f"❌ خطا: {e}", reply_markup=admin_menu())
        context.user_data.clear()
        return

    if text == "📋 سفارش‌های در انتظار":
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("SELECT id, username, price, created_at, receipt, discount_code FROM orders WHERE status='pending'")
        rows = c.fetchall()
        conn.close()
        if not rows:
            await update.message.reply_text("📭 سفارشی نیست.", reply_markup=admin_menu())
            return
        msg = "📋 در انتظار:\n\n"
        for r in rows:
            rcpt = "✅" if r[4] else "⏳"
            disc = f"|🎟️{r[5]}" if r[5] else ""
            msg += f"#{r[0]}|@{r[1]}|{r[2]:,}ت{disc}|{rcpt}\n"
        await update.message.reply_text(msg, reply_markup=admin_menu())

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id == ADMIN_CHAT_ID: return
    text = update.message.text
    if text == "❌ انصراف و بازگشت":
        context.user_data.clear()
        await update.message.reply_text("🔙 منوی اصلی", reply_markup=main_menu(False))
        return
    if await handle_discount_code_input(update, context): return
    if "waiting_receipt" in context.user_data:
        await handle_receipt(update, context)

def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()
    app.job_queue.run_repeating(cancel_expired_orders, interval=config.get("CHECK_INTERVAL_SECONDS", 60), first=10)
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

    mkdir -p data
    cd ..
}

install_bot() {
    echo -e "${YELLOW}📦 در حال نصب ربات...${NC}"
    
    if [ -d "$BOT_DIR" ] && [ -f "$BOT_DIR/docker-compose.yml" ]; then
        echo -e "${YELLOW}⚠️  ربات قبلاً نصب شده است.${NC}"
        read -p "آیا می‌خواهید حذف و از اول نصب شود؟ (y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo -e "${YELLOW}انصراف از نصب مجدد.${NC}"
            return
        fi
        
        echo -e "${BLUE}🗑️ در حال حذف نصب قبلی...${NC}"
        cd $BOT_DIR
        docker compose down --rmi all -v 2>/dev/null || true
        cd ..
        rm -rf $BOT_DIR
        echo -e "${GREEN}✅ نصب قبلی حذف شد.${NC}"
    fi
    
    install_docker
    create_bot_files
    cd $BOT_DIR
    
    echo ""
    read -p "توکن ربات تلگرام: " BOT_TOKEN
    read -p "آیدی عددی ادمین: " ADMIN_ID
    echo "BOT_TOKEN=$BOT_TOKEN" > .env
    echo "ADMIN_ID=$ADMIN_ID" >> .env
    
    docker compose up -d --build
    cd ..
    echo -e "${GREEN}✅ ربات نصب و اجرا شد!${NC}"
}

uninstall_bot() {
    echo -e "${RED}🗑️ حذف کامل ربات${NC}"
    
    if [ ! -d "$BOT_DIR" ]; then
        echo -e "${YELLOW}⚠️ رباتی نصب نشده است.${NC}"
        return
    fi
    
    echo -e "${YELLOW}⚠️  هشدار: این عملیات تمام فایل‌ها و دیتای ربات را حذف می‌کند!${NC}"
    read -p "آیا مطمئن هستید؟ (برای تایید 'DELETE' را تایپ کنید): " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        echo -e "${YELLOW}انصراف از حذف.${NC}"
        return
    fi
    
    echo -e "${BLUE}🔄 در حال توقف و حذف کانتینر...${NC}"
    cd $BOT_DIR
    docker compose down --rmi all -v 2>/dev/null || true
    cd ..
    
    echo -e "${BLUE}🗑️ در حال حذف فایل‌ها...${NC}"
    rm -rf $BOT_DIR
    
    echo -e "${GREEN}✅ ربات به طور کامل حذف شد!${NC}"
}

update_bot() {
    echo -e "${YELLOW}🔄 در حال آپدیت ربات...${NC}"
    
    if [ -d "$BOT_DIR/data" ]; then
        echo -e "${BLUE}📂 بکاپ موقت از دیتا...${NC}"
        cp -r $BOT_DIR/data /tmp/bot_data_backup
        if [ -f "$BOT_DIR/.env" ]; then
            cp $BOT_DIR/.env /tmp/bot_env_backup
        fi
    fi
    
    create_bot_files
    
    if [ -d "/tmp/bot_data_backup" ]; then
        echo -e "${BLUE}📂 بازگردانی دیتا...${NC}"
        rm -rf $BOT_DIR/data
        mv /tmp/bot_data_backup $BOT_DIR/data
        if [ -f "/tmp/bot_env_backup" ]; then
            mv /tmp/bot_env_backup $BOT_DIR/.env
        fi
    fi
    
    cd $BOT_DIR
    docker compose down 2>/dev/null || true
    docker compose up -d --build
    cd ..
    echo -e "${GREEN}✅ ربات آپدیت شد! (دیتا حفظ شد)${NC}"
}

start_bot() {
    echo -e "${YELLOW}▶️ در حال استارت ربات...${NC}"
    cd $BOT_DIR
    docker compose up -d
    cd ..
    echo -e "${GREEN}✅ ربات استارت شد!${NC}"
}

restart_bot() {
    echo -e "${YELLOW}🔁 در حال ری‌استارت ربات...${NC}"
    cd $BOT_DIR
    docker compose restart
    cd ..
    echo -e "${GREEN}✅ ربات ری‌استارت شد!${NC}"
}

stop_bot() {
    echo -e "${YELLOW}⏹️ در حال توقف ربات...${NC}"
    cd $BOT_DIR
    docker compose down
    cd ..
    echo -e "${GREEN}✅ ربات متوقف شد!${NC}"
}

backup_bot() {
    echo -e "${YELLOW}💾 در حال بکاپ گرفتن...${NC}"
    mkdir -p $BACKUP_DIR
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
    
    if [ ! -d "$BOT_DIR/data" ]; then
        echo -e "${RED}❌ پوشه data وجود ندارد!${NC}"
        return
    fi
    
    tar -czvf $BACKUP_FILE -C $BOT_DIR data .env 2>/dev/null || tar -czvf $BACKUP_FILE -C $BOT_DIR data 2>/dev/null
    echo -e "${GREEN}✅ بکاپ ذخیره شد: $BACKUP_FILE${NC}"
}

restore_backup() {
    echo -e "${YELLOW}📥 بازیابی بکاپ...${NC}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ پوشه بکاپ وجود ندارد!${NC}"
        return
    fi
    
    echo -e "${BLUE}📋 لیست بکاپ‌ها:${NC}"
    echo ""
    
    BACKUPS=($(ls -t $BACKUP_DIR/*.tar.gz 2>/dev/null))
    
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo -e "${RED}❌ هیچ بکاپی وجود ندارد!${NC}"
        return
    fi
    
    for i in "${!BACKUPS[@]}"; do
        FILENAME=$(basename "${BACKUPS[$i]}")
        FILESIZE=$(du -h "${BACKUPS[$i]}" | cut -f1)
        echo -e "  ${YELLOW}$((i+1)))${NC} $FILENAME ${BLUE}($FILESIZE)${NC}"
    done
    
    echo ""
    read -p "شماره بکاپ (0=انصراف): " choice
    
    if [ "$choice" == "0" ] || [ -z "$choice" ]; then
        echo -e "${YELLOW}انصراف.${NC}"
        return
    fi
    
    INDEX=$((choice-1))
    
    if [ $INDEX -lt 0 ] || [ $INDEX -ge ${#BACKUPS[@]} ]; then
        echo -e "${RED}❌ شماره نامعتبر!${NC}"
        return
    fi
    
    SELECTED_BACKUP="${BACKUPS[$INDEX]}"
    echo -e "${YELLOW}⚠️ دیتای فعلی جایگزین می‌شود!${NC}"
    read -p "ادامه؟ (y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${YELLOW}انصراف.${NC}"
        return
    fi
    
    cd $BOT_DIR 2>/dev/null && docker compose down 2>/dev/null
    cd ..
    
    mkdir -p $BOT_DIR
    [ -d "$BOT_DIR/data" ] && rm -rf $BOT_DIR/data
    
    tar -xzvf "$SELECTED_BACKUP" -C $BOT_DIR
    
    cd $BOT_DIR
    docker compose up -d
    cd ..
    
    echo -e "${GREEN}✅ بازیابی کامل شد!${NC}"
}

show_logs() {
    cd $BOT_DIR
    docker compose logs -f --tail=50
    cd ..
}

show_status() {
    cd $BOT_DIR
    echo -e "${BLUE}📊 وضعیت:${NC}"
    docker compose ps
    cd ..
}

while true; do
    show_menu
    read -p "گزینه: " choice
    echo ""
    
    case $choice in
        1) install_bot ;;
        2) update_bot ;;
        3) start_bot ;;
        4) restart_bot ;;
        5) stop_bot ;;
        6) backup_bot ;;
        7) restore_backup ;;
        8) show_logs ;;
        9) show_status ;;
        10) uninstall_bot ;;
        0) echo -e "${GREEN}خداحافظ! 👋${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ نامعتبر!${NC}" ;;
    esac
    
    echo ""
    read -p "Enter برای ادامه..."
done
