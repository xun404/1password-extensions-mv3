#!/bin/bash
# ============================================================================
# 1Password 6 "Browser's runtime signature invalid (103)" fix script
# 1Password 6 错误 103（Browser's runtime signature invalid）修复脚本
#
#   Root cause / 根因:
#     1Password 6's OnePasswordCore only trusts Chrome signed with the
#     2018-era "Google, Inc. (EQHXZ8M8AV)" Developer ID cert. Modern Chrome
#     is signed by "Google LLC (EQHXZ8M8AV)", so the native-messaging
#     runtime-signature check fails -> error 103.
#
#   Interactive flow / 交互流程 (3 steps):
#     Step 1 - Select language (auto-detect as fallback)
#     Step 2 - Review procedure + environment checks, confirm to continue
#     Step 3 - Final execution confirmation, then modify files
#
#   What the script does / 脚本做什么:
#     1. Backs up OnePasswordCore
#     2. Equally-length replaces the cert name in 2 requirement strings
#        (Google, Inc. -> Google LLC). Signature verification is KEPT.
#     3. Verifies the patched requirement parses AND that this machine's
#        Chrome satisfies it (SecStaticCodeCheckValidityWithErrors).
#     4. Re-signs ONLY the OnePasswordCore framework (ad-hoc by default).
#        Nothing else in the app bundle is touched.
#
#   Usage / 用法:
#     bash fix_1password6.sh                    # ad-hoc signing, no cert
#     bash fix_1password6.sh "MyCertName"       # sign with a keychain cert
#     bash fix_1password6.sh --lang=zh|en       # skip language prompt
#     bash fix_1password6.sh -h | --help
#
#   Rollback / 回滚:
#     cp "$BACKUP" "$CORE" && codesign -f -s - "$FRAMEWORK_DIR"
# ============================================================================
set -euo pipefail

APP_DIR="/Applications/1Password 6.app"
CORE="$APP_DIR/Contents/Frameworks/OnePasswordCore.framework/Versions/A/OnePasswordCore"
FRAMEWORK_DIR="$APP_DIR/Contents/Frameworks/OnePasswordCore.framework"
OLD_CN="Developer ID Application: Google, Inc. (EQHXZ8M8AV)"
NEW_CN="Developer ID Application: Google LLC (EQHXZ8M8AV)"
CHROME_APP="/Applications/Google Chrome.app"

# ---------------------------------------------------------------------------
# 参数解析 / argument parsing
# ---------------------------------------------------------------------------
CERT="-"                      # default: ad-hoc, no certificate needed
LANG_ARG=""
for a in "$@"; do
  case "$a" in
    -h|--help)
      sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --lang=zh|--lang=en) LANG_ARG="${a#--lang=}" ;;
    *) CERT="$a" ;;
  esac
done

# ===========================================================================
# Step 1/3: 选择语言 / Select language
# ===========================================================================
L="${L:-}"
if [ -n "$LANG_ARG" ]; then
  L="$LANG_ARG"
elif [ -z "$L" ]; then
  AUTO_DETECT() {
    SYS_LANG=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '1p' | tr -d ' "')
    case "$SYS_LANG" in
      zh*) L="zh" ;;
      *)   L="en" ;;
    esac
  }
  if [ -t 0 ]; then
    echo "============================================================"
    echo " Step 1/3 - Select language / 选择语言"
    echo "============================================================"
    echo "   [1] 中文"
    echo "   [2] English"
    read -r -p "   Please choose / 请选择 [1/2, Enter=auto]: " LCHOICE || true
    case "$LCHOICE" in
      1) L="zh" ;;
      2) L="en" ;;
      *) AUTO_DETECT ;;
    esac
  else
    AUTO_DETECT
  fi
fi

# B zh-text en-text : bilingual printer
B() { if [ "$L" = "zh" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# ---------------------------------------------------------------------------
# Step 2/3: 流程说明 + 只读环境检查 / procedure + read-only environment checks
# ---------------------------------------------------------------------------
CORE_STATE=""        # pristine | patched | unknown
CORE_TEAM=""
IS_RUNNING=0
CAN_WRITE=0
NEED_SUDO=0
CHROME_VER=""
CHROME_CN=""
IDENT_OK=0

echo
echo "============================================================"
echo " Step 2/3 - $(B '流程与环境检查（只读，不会做任何修改）' 'Procedure & environment checks (read-only)')"
echo "============================================================"
echo
echo "$(B '  流程' '  Procedure'):"
echo "    a. $(B '备份' 'Back up') OnePasswordCore"
echo "    b. $(B '等长替换 2 处证书名（保留签名校验，只放行 Google LLC 签名的 Chrome）' 'Replace cert name in 2 spots, equal length (verification kept; only Google LLC-signed Chrome accepted)')"
echo "    c. $(B '在线校验: requirement 可解析 + 本机 Chrome 满足新白名单' 'Online verify: requirement parses + this machine Chrome satisfies it')"
echo "    d. $(B '只对框架重新签名（App 其余部分一律不动）' 'Re-sign ONLY the framework (nothing else touched)')"
echo
echo "$(B '  ---- 环境检查结果 ----' '  ---- Environment checks ----')"

# 1. macOS
echo "  - macOS: $(sw_vers -productVersion 2>/dev/null || echo ?)"

# 2. App / framework exists
if [ -f "$CORE" ]; then
  APP_VER=$(defaults read "$APP_DIR/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
  echo "  - $(B '1Password' '1Password'): $APP_DIR ($(B '版本' 'version') $APP_VER)"
else
  echo "  - $(B '错误: 找不到' 'ERROR: missing') $CORE"
  exit 1
fi

# 3. Python3 + patch state (pure byte inspection, nothing modified)
if command -v python3 >/dev/null 2>&1; then
  PY="ok"
else
  PY="missing"
fi
echo "  - Python3: ${PY}"
if [ "$PY" = "ok" ]; then
  CORE_STATE="unknown"
  if python3 -c "
import sys
d = open(r'$CORE','rb').read()
old = b'$OLD_CN'; new = b'$NEW_CN'
n_old, n_new = d.count(old), d.count(new)
sys.exit(0 if (n_old == 2 and n_new == 0) else (1 if (n_old == 0 and n_new == 2) else 2))
"; then
    CORE_STATE="pristine"
  elif [ "$?" -eq 1 ]; then
    CORE_STATE="patched"
  fi
fi
case "$CORE_STATE" in
  pristine) echo "  - $(B '目标文件: 原版（将替换 2 处证书名）' 'Target file: pristine (2 cert names will be replaced)')" ;;
  patched)  echo "  - $(B '目标文件: 已打过补丁（将跳过替换，仅校验+重签）' 'Target file: already patched (skip replace, verify+re-sign only)')" ;;
  *)        echo "  - $(B '错误: 文件状态无法识别（不是预期版本），已中止' 'ERROR: file state unrecognized (unexpected build), aborting')"; exit 1 ;;
esac

# 4. Current signature team
CORE_TEAM=$(codesign -dv "$CORE" 2>/dev/null | awk -F= '/TeamIdentifier/{print $2}')
[ -z "$CORE_TEAM" ] && CORE_TEAM="adhoc/not set"
echo "  - $(B '当前框架签名 TeamID' 'Current framework TeamID'): $CORE_TEAM"

# 5. Chrome
if [ -d "$CHROME_APP" ]; then
  CHROME_VER=$(defaults read "$CHROME_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
  CHROME_CN=$(codesign -dv --verbose=4 "$CHROME_APP" 2>&1 | awk -F= '/^Authority=Developer ID/{if (!seen) {print $2; seen=1}}')
  echo "  - Chrome: $CHROME_VER  (leaf CN: ${CHROME_CN:-?})"
else
  echo "  - $(B '警告: 未找到' 'WARNING: not found') $CHROME_APP"
fi

# 6. 1Password must not be running
if pgrep -f "/Applications/1Password 6.app" >/dev/null 2>&1; then
  IS_RUNNING=1
  echo "  - $(B '警告: 1Password / mini 正在运行，执行前会被要求退出' 'WARNING: 1Password / mini is running; you must quit it before execution')"
else
  echo "  - $(B '1Password: 未运行' '1Password: not running')"
fi

# 7. Write permission
if [ "$(id -u)" -eq 0 ]; then
  CAN_WRITE=1
elif [ -w "$CORE" ]; then
  CAN_WRITE=1
else
  NEED_SUDO=1
  echo "  - $(B '写入权限: 需要 sudo（确认后会自动重新提权执行）' 'Write access: sudo required (will re-exec elevated after confirmation)')"
fi
[ "$CAN_WRITE" = "1" ] && echo "  - $(B '写入权限: 可写' 'Write access: writable')"

# 8. Signing identity
if [ "$CERT" = "-" ]; then
  IDENT_OK=1
  echo "  - $(B '签名身份: ad-hoc（无需证书）' 'Signing identity: ad-hoc (no certificate needed)')"
else
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    KC="/Users/$SUDO_USER/Library/Keychains/login.keychain-db"
    KC_ARGS=$([ -f "$KC" ] && echo "--keychain $KC" || echo "")
  else
    KC_ARGS=""
  fi
  if security find-identity -v -p codesigning $KC_ARGS 2>/dev/null | grep -F "\"$CERT\"" >/dev/null; then
    IDENT_OK=1
    echo "  - $(B '签名身份' 'Signing identity'): \"$CERT\""
  else
    echo "  - $(B '错误: 钥匙串里找不到证书' 'ERROR: certificate not found in keychain'): \"$CERT\""
    echo "    $(B '用 ad-hoc 方式运行: bash' 'Run with ad-hoc instead: bash') $0 -"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2 确认 / step 2 confirmation  ->  Step 3/3 最终确认 / final confirmation
# (提权重跑后 CONFIRMED=1，跳过两次确认)
# ---------------------------------------------------------------------------
BACKUP="${CORE}.backup-$(date +%Y%m%d-%H%M%S)"

if [ "${CONFIRMED:-0}" != "1" ]; then
  echo
  read -r -p "$(B '  Step 2 确认: 流程与环境检查如上，继续? [y/N]: ' '  Step 2 confirm: procedure & checks above look good, continue? [y/N]: ')" ANS || true
  case "$ANS" in
    y|Y|yes|YES) ;;
    *) echo "$(B '已取消。' 'Cancelled.')"; exit 0 ;;
  esac

  echo
  echo "============================================================"
  echo " Step 3/3 - $(B '执行内容最终确认' 'Final execution confirmation')"
  echo "============================================================"
  echo "  a. $(B '备份' 'Back up'): $BACKUP"
  if [ "$CORE_STATE" = "patched" ]; then
    echo "  b. $(B '跳过字节替换（已打过补丁）' 'Skip byte replace (already patched)')"
  else
    echo "  b. $(B '替换 2 处证书名' 'Replace 2 cert names'):"
    echo "       '$OLD_CN'"
    echo "       -> '$NEW_CN'"
  fi
  echo "  c. $(B '校验 requirement + 本机 Chrome' 'Verify requirement + this machine Chrome')"
  echo "  d. $(B '重签' 'Re-sign'): codesign -f -s \"$CERT\" $FRAMEWORK_DIR"
  [ "$NEED_SUDO" = "1" ] && echo "  e. $(B '先通过 sudo 提权（会提示输入密码）' 'Elevate via sudo first (password prompt)')"
  [ "$IS_RUNNING" = "1" ] && echo "  ! $(B '执行期间若 1Password 仍在运行会直接中止' 'Execution aborts if 1Password is still running')"
  echo

  read -r -p "$(B '  Step 3 确认: 现在执行? 输入 y 回车开始 [y/N]: ' '  Step 3 confirm: execute now? Type y and Enter to start [y/N]: ')" ANS || true
  case "$ANS" in
    y|Y|yes|YES) ;;
    *) echo "$(B '已取消。' 'Cancelled.')"; exit 0 ;;
  esac
fi

# ---------------------------------------------------------------------------
# 执行 / execution
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ] && [ "$NEED_SUDO" = "1" ]; then
  echo "$(B '==> 正在通过 sudo 提权重新执行...' '==> Re-executing with sudo...')"
  exec sudo CONFIRMED=1 L="$L" bash "$0" "$@"
fi

echo
echo "============================================================"
echo "$(B '==> 执行中' '==> Executing')"
echo "============================================================"

# 1. 1Password must be quit
if pgrep -f "/Applications/1Password 6.app" >/dev/null 2>&1; then
  echo "$(B '错误: 1Password / mini 仍在运行。请先彻底退出（含菜单栏 mini）再重跑。' 'ERROR: 1Password / mini still running. Quit it (incl. menu bar mini) and re-run.')"
  exit 1
fi

# 2. Backup
echo "==> $(B '备份' 'Backing up')"
cp -p "$CORE" "$BACKUP"
echo "    -> $BACKUP"

# 3. Patch (or skip if already patched)
echo "==> $(B '字节补丁' 'Byte patch')"
python3 - "$CORE" <<'PYEOF'
import sys
path = sys.argv[1]
d = bytearray(open(path, "rb").read())
OLD = b'Developer ID Application: Google, Inc. (EQHXZ8M8AV)'
NEW = b'Developer ID Application: Google LLC (EQHXZ8M8AV)'
assert len(OLD) == 51 and len(NEW) == 49
p1 = d.find(OLD)
p2 = d.find(OLD, p1 + 1) if p1 != -1 else -1

if p1 == -1 and d.count(NEW) == 2:
    print("    already patched, skipping replace.")
    sys.exit(0)

assert p1 == 0x15379D, "p1 offset mismatch: %#x" % p1
assert p2 == 0x1538AB, "p2 offset mismatch: %#x" % p2

for p in (p1, p2):
    # Original layout: OLD(51) + '"' + tail. Replace the 54-byte region
    # with NEW + '"  ' + original last 2 bytes, so the CN inside quotes
    # matches exactly and the requirement stays syntactically valid.
    d[p:p + 54] = NEW + b'"  ' + d[p + 52:p + 54]
open(path, "wb").write(d)

v = open(path, "rb").read()
assert v.find(OLD) == -1 and v.count(NEW) == 2
assert v[p1 + 49:p1 + 57] == b'"  ))\x00an', repr(v[p1 + 49:p1 + 57])
assert v[p2 + 49:p2 + 58] == b'"  ) or (', repr(v[p2 + 49:p2 + 58])
assert v[0x1536D4:0x1536F0].startswith(b"anchor apple generic")
assert v[0x1537D4:0x1537F0].startswith(b"anchor apple generic")
assert v[0x154200:0x15421C].startswith(b"anchor apple generic")
print("    replaced 2 cert names OK.")
PYEOF

# 4. Verify: requirement parses + this machine's Chrome satisfies it
echo "==> $(B '校验新 requirement' 'Verifying new requirement')"
python3 - "$CORE" <<'PYEOF'
import sys, ctypes
path = sys.argv[1]
v = open(path, "rb").read()

CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
SEC = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
kCFStringEncodingUTF8 = 0x08000100

CF.CFStringCreateWithBytes.restype = ctypes.c_void_p
CF.CFStringCreateWithBytes.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long, ctypes.c_uint32, ctypes.c_bool]
SEC.SecRequirementCreateWithString.restype = ctypes.c_int32
SEC.SecRequirementCreateWithString.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
CF.CFURLCreateFromFileSystemRepresentation.restype = ctypes.c_void_p
CF.CFURLCreateFromFileSystemRepresentation.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_bool]
SEC.SecStaticCodeCreateWithPath.restype = ctypes.c_int32
SEC.SecStaticCodeCreateWithPath.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
SEC.SecStaticCodeCheckValidityWithErrors.restype = ctypes.c_int32
SEC.SecStaticCodeCheckValidityWithErrors.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]

s = v[0x1536D4:v.find(b"\x00", 0x1536D4)]
buf = ctypes.create_string_buffer(s)
cfstr = CF.CFStringCreateWithBytes(None, buf, len(s), kCFStringEncodingUTF8, False)
req = ctypes.c_void_p()
st = SEC.SecRequirementCreateWithString(cfstr, 0, ctypes.byref(req))
assert st == 0 and req.value, "requirement parse failed: %d" % st
print("    requirement parses OK.")

chrome = b"/Applications/Google Chrome.app"
url = CF.CFURLCreateFromFileSystemRepresentation(None, chrome, len(chrome), False)
code = ctypes.c_void_p()
st = SEC.SecStaticCodeCreateWithPath(url, 0, ctypes.byref(code))
assert st == 0 and code.value, "cannot read Chrome static code: %d" % st
err = ctypes.c_void_p()
st = SEC.SecStaticCodeCheckValidityWithErrors(code, 0, req, ctypes.byref(err))
assert st == 0, "this Chrome does NOT satisfy the patched requirement: %d" % st
print("    this machine's Chrome satisfies the patched requirement.")
PYEOF

# 5. Re-sign framework only
echo "==> $(B '只对框架重新签名' 'Re-signing framework only')"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$CERT" != "-" ]; then
  KC="/Users/$SUDO_USER/Library/Keychains/login.keychain-db"
  KC_ARGS=$([ -f "$KC" ] && echo "--keychain $KC" || echo "")
else
  KC_ARGS=""
fi
codesign -f $KC_ARGS -s "$CERT" "$FRAMEWORK_DIR"
codesign -dv --verbose=2 "$CORE" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier" || true

# 6. Summary
echo
echo "============================================================"
echo "$(B '==> 完成' '==> Done')"
echo "============================================================"
echo "$(B '  1. 启动 1Password 6（菜单栏会出现 mini）' '  1. Launch 1Password 6 (mini appears in menu bar)')"
echo "$(B '  2. Chrome 打开 chrome://extensions，点 1Password 扩展的刷新图标' '  2. Open chrome://extensions and click the reload icon on the 1Password extension')"
echo "$(B '  3. 打开登录页测试填充' '  3. Open a login page to test filling')"
echo
echo "$(B '回滚方法' 'Rollback'):"
echo "  cp \"$BACKUP\" \"$CORE\" && codesign -f $KC_ARGS -s \"$CERT\" \"$FRAMEWORK_DIR\""
