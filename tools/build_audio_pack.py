# -*- coding: utf-8 -*-
"""
《摄伏》音效资源管线（2026-10-09 重定 · 第三版）
--------------------------------------------------------------------------
把 D:/mycp/dounment/17_音频音效 里的素材按「最合适」挑出来，
拷进 SheFu/assets/audio/，文件名即 Sfx.gd 的 API 名。

【本版最重要的两条规则】

1. **只允许使用现存素材，且明确排除 RPG 包**
   用户已删除 `RPG游戏音效素材包` / `界面操作音效素材包` / `碰撞冲击音效素材包`
   / `科幻游戏音效素材包`。本管线只从下面这些现存目录里取：

     UI界面音效素材包/Audio/              界面点击 / 悬停 / 开关（51 个 ogg）
     游戏动画音效全集/…/interface 界面/    菜单开合 / 决定取消 / 翻书 / 升级 / 拾取
     游戏动画音效全集/…/技能音效/          19 类技能（金木水火土石雷风光气爆冰毒…）
     游戏动画音效全集/…/环境音效/          场所氛围（拜神 / 敬鬼 揭晓用）
     雷电/雷电/                            雷声专库
     怪物/怪物/                            鬼怪吼叫 + 龙吟

   任何一条映射引用了不存在的源文件，脚本**直接报错退出**（不再静默跳过）。

2. **禁止随机播放，一律固定**
   旧版是「同名变体 <name>_1/_2 随机取一个」，用户明确否掉：
   同一个操作每次听起来都不一样，等于玩家永远记不住反馈。
   现在 **一个音效名 = 一个固定文件**。
   唯一例外是「同类型」的成组素材（雷电1/雷电2 这种），本管线把它们
   拆成独立名字（bolt / bolt_deep）显式登记，由调用方决定用哪一条，
   依然不是随机。

命名约定：assets/audio/<key>.<ext>，扩展名保持源文件原样
（.ogg / .wav / .mp3 Godot 都能直接导入）。

用法：
    python tools/build_audio_pack.py
"""
import os
import shutil
import struct

SRC = r"D:/mycp/dounment/17_音频音效"
PROJ = r"D:/mycp/Edgedownload/shefu/SheFu"
OUT = os.path.join(PROJ, "assets", "audio")

# ---------------------------------------------------------------- 源目录
UI = "UI界面音效素材包/Audio/"
IFACE = "游戏动画音效全集/游戏动画音效全集/interface 界面/"
SKILL = "游戏动画音效全集/游戏动画音效全集/技能音效/"
AMB = "游戏动画音效全集/游戏动画音效全集/环境音效/"
THUNDER = "雷电/雷电/"
MON = "怪物/怪物/"

# ---------------------------------------------------------------- 映射表
# key = Sfx.gd 的音效名（== assets/audio/<key>.<ext>）
# val = 源文件相对路径（单个文件 —— 固定音效，不随机）
PACK = {
    # ================= 界面 / 交互（优先 UI界面音效素材包） =================
    "ui_click":      UI + "click1.ogg",
    "ui_hover":      UI + "rollover2.ogg",
    "ui_select":     UI + "mouseclick1.ogg",
    "ui_toggle":     UI + "switch2.ogg",
    "ui_tick":       UI + "click3.ogg",
    "ui_confirm":    IFACE + "决定－xh20070419.wav",
    "ui_back":       IFACE + "取消－xh20070419.wav",
    "ui_open":       IFACE + "打开菜单1－xh20070511.wav",
    "ui_close":      IFACE + "关闭菜单1－xh20070511.wav",
    "ui_reveal":     IFACE + "按钮类3－mcx20070509.wav",
    "ui_fullscreen": IFACE + "打开声音“呯”声－xh20070419.wav",
    "ui_error":      SKILL + "11物体机关类/错误提示1-xys20070411.wav",
    "ui_scroll":     SKILL + "12其他类/摩擦声1－xh20070511.wav",

    # ================= 卡牌本体（纸牌要像纸牌） =================
    # 抽牌：翻书页
    "draw":          IFACE + "打开书－xh20070419.wav",
    # 出牌落场：合上书 / 牌拍在桌面
    "play":          IFACE + "合上开书－xh20070419.wav",
    # 【财】增减：金币
    "coin":          IFACE + "掠夺大的硬币－xh20070419.wav",
    # 掷骰（拜神 / 敬鬼）：金属碰撞后掉落
    "dice":          SKILL + "11物体机关类/金属碰撞－掉落－YS20070426.wav",

    # ================= 战斗（金 / 木 / 土石 / 击中） =================
    "attack":        SKILL + "01金/特技剑-WQ20070510.wav",
    "slash":         SKILL + "01金/剑气类法术-mcx20070517.wav",
    "hit":           SKILL + "技能击中类效果/其他击中4－mcx20070509.wav",
    "smash":         SKILL + "05土石类/击中－爆炸－石块碎裂1－mcx20060416.wav",
    "clash":         SKILL + "01金/金属碰撞1-mcx20070511.wav",
    "quake":         SKILL + "05土石类/土石塌方-YS070517.wav",
    "wood":          SKILL + "02木/木头击中－YS070517.wav",

    # ================= 天 / 地 / 人 技能 fx（与 CCard.fx_for_type 一一对应） =================
    "fire":          SKILL + "04火/火属性法杖攻击-YS070516.wav",
    "wind":          SKILL + "07风类/小型飓风-XYS20070425.wav",
    # 雷：用户指名的专库（同类型成组，这里显式固定用「惊雷-短」）
    "bolt":          THUNDER + "雷电1-惊雷-短-ltt20070412.wav",
    "bolt_deep":     THUNDER + "雷电2-闷雷-ltt20070412.wav",
    "arrow":         SKILL + "01金/高频开始－射出－击中－mcx20070416.wav",
    # 鬼怪咆哮：怪物库（大型怪物 / 怪物的吼叫）
    "roar":          MON + "03大型怪物/怪物的吼叫－YS070517.wav",
    # 龙（辰龙 / 青龙 / 亢金龙 / 金龙 / 黄龙）：龙吟
    "dragon":        "怪物/龙吟.mp3",
    "moon":          SKILL + "08光/光魔法、神圣感-xys20070511.wav",
    "soul":          SKILL + "19诅咒类/诡异的空间感类似诅咒的魔法-YS070518.wav",
    "poison":        SKILL + "15毒/毒气灵力类法术1-mcx20070517.wav",
    "chain":         SKILL + "01金/金属块摩擦2-mcx20070511.wav",
    "seal":          SKILL + "19诅咒类/强烈诅咒－xh20070509.wav",
    "shield":        SKILL + "12其他类/魔法盾释放-YS070522.wav",
    "purge":         SKILL + "10爆炸/亡灵被驱散1-XYS20070425.wav",
    "revive":        SKILL + "18治愈系/佛光普照－xh20070516.wav",
    "summon":        SKILL + "16召唤类/召唤狼-xys20070425.wav",
    "beast":         SKILL + "16召唤类/魔法释放－狮子吼叫－YS20070426.wav",
    "heal":          SKILL + "18治愈系/治疗法术zth07523.wav",
    "blood":         SKILL + "17魔法灵力类/吸血魔法－YS070511.wav",
    # 增益 / 升级：素材库自带「升级声」，正对场景
    "buff":          IFACE + "升级声－xh20070419.wav",
    "freeze":        SKILL + "13冰/冰-爆裂-LTT20070428.wav",

    # ================= 回合 / 结局 =================
    "turn":          IFACE + "开始的钟声－xh20070419.wav",
    "win":           IFACE + "完成人物特性－xh20070419.wav",
    "lose":          IFACE + "任务失败-xys20070508.wav",
    # 起乩 / 天命显现：诡异的魔法释放
    "synth":         SKILL + "17魔法灵力类/奇异的魔法释放-YS070522.wav",
    "bell":          SKILL + "12其他类/起义铃-xh20070425.wav",

    # ================= 拜神 / 敬鬼 揭晓（环境音效） =================
    # 请天：钟声泛音的空旷感（神圣、开阔）
    "worship_shen":  AMB + "15光感/冰冷类似钟声泛音的空旷感－YS2007058.wav",
    # 请地：呼啸里带鬼怪喘气（阴森）
    "worship_gui":   AMB + "16气流声/呼啸-带有鬼怪喘气-LTT20070517.wav",
}


def strip_loop_chunks(path: str) -> bool:
    """剥掉 wav 里的 smpl / cue 循环标记 chunk，返回是否真的剥过。

    为什么需要：部分素材（敬鬼 worship_gui / 雷电 bolt）的 wav 自带 smpl loop
    标记，Godot 导入器在 edit/loop_mode=0（Detect From WAV）下会读走它、把音频
    导成向前循环 —— 敬鬼那声呼啸喘气就会一直响。从源头把标记剥掉，导入时自然
    不循环；运行时 Sfx.gd 里还有一道兜底（锁死 loop_mode=LOOP_DISABLED）。
    """
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return False
    out = bytearray(data[:12])
    i = 12
    removed = False
    while i + 8 <= len(data):
        cid = data[i:i + 4]
        size = struct.unpack("<I", data[i + 4:i + 8])[0]
        if cid in (b"smpl", b"cue "):
            removed = True
        else:
            out += data[i:i + 8 + size]
        i += 8 + size + (size & 1)  # chunk 按 2 字节对齐
    if not removed:
        return False
    struct.pack_into("<I", out, 4, len(out) - 8)  # 修正 RIFF 总长
    with open(path, "wb") as f:
        f.write(out)
    return True


def main() -> None:
    os.makedirs(OUT, exist_ok=True)

    # ---------- 0. 前置校验：任何一条映射引用了不存在的源文件都要吼出来 ----------
    bad = []
    for name, rel in PACK.items():
        if not os.path.exists(os.path.join(SRC, rel)):
            bad.append("%s <- %s" % (name, rel))
    if bad:
        print("[FAIL] 以下映射引用了不存在的源文件（素材被删/改名？）：")
        for b in bad:
            print("   -", b)
        raise SystemExit(1)

    # ---------- 1. 清空旧资源（含 .import，避免残留已废弃的音效名） ----------
    removed = 0
    for fn in sorted(os.listdir(OUT)):
        if fn.endswith((".wav", ".ogg", ".mp3")) or fn.endswith(".import"):
            os.remove(os.path.join(OUT, fn))
            removed += 1
    print(f"[CLEAN] 清空 assets/audio 旧文件 {removed} 个")

    # ---------- 2. 拷贝（保持源扩展名） ----------
    copied = 0
    total = 0
    stripped = []
    for name, rel in PACK.items():
        src = os.path.join(SRC, rel)
        ext = os.path.splitext(rel)[1].lower()
        dst = os.path.join(OUT, name + ext)
        shutil.copy2(src, dst)
        copied += 1
        total += os.path.getsize(dst)
        # 剥掉 wav 自带的循环标记（smpl/cue），防止 Godot 导入时自动循环
        if ext == ".wav" and strip_loop_chunks(dst):
            stripped.append(name)

    print(f"[COPY] 写入 {copied} 个音效 -> assets/audio/  合计 {total / 1e6:.1f} MB")
    if stripped:
        print(f"[LOOP] 剥掉循环标记（smpl/cue）的音效：{', '.join(stripped)}")
    print("[OK] 素材来源：UI界面音效素材包 / interface 界面 / 技能音效 / 环境音效 / "
          "雷电 / 怪物（**未使用 RPG 游戏音效素材包**）")
    print("[OK] 固定音效：一名一文件，不做随机变体")


if __name__ == "__main__":
    main()
