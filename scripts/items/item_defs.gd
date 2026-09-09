class_name ItemDefs
extends RefCounted
## 道具图鉴：六件"半成品手工感"的荒诞道具。纯静态数据 + 纯静态逻辑。
## 设计守则：每个道具都是把 Bug 包装成可控技能——威力不重要，好笑才重要。

const IDS: Array[String] = ["potion", "boots", "horn", "rewind", "bomb", "whistle", "wolf_tooth", "wolf_skin", "wolf_bone"]

## 草堆可刷出的道具（哨子是"任务奖励/商店特供"，不进草堆池）
const PILE_IDS: Array[String] = ["potion", "boots", "horn", "rewind", "bomb"]

static var INFO := {
	"potion": {
		"name": "穿模药水",
		"glyph": "药",
		"color": Color(0.35, 0.9, 0.45),
		"desc": "饮用后 5 秒内可以穿过墙和 NPC——一切讲道理的东西都拦不住你（地除外，地太厚，下个版本的事）。",
		"quip": "你捡到了一瓶绿油油的玩意儿，喝吗？（按 1/2/3 使用）",
	},
	"boots": {
		"name": "反向重力靴",
		"glyph": "靴",
		"color": Color(0.9, 0.3, 0.3),
		"desc": "使用后重力翻转 8 秒，倒着往上走。这地图没有天花板——这就是问题所在。",
		"quip": "一只红靴子从天上掉下来，左右还是反着穿的。",
	},
	"horn": {
		"name": "弹射号角",
		"glyph": "号",
		"color": Color(0.95, 0.65, 0.2),
		"desc": "吹响后原地爆炸，把自己炸上天（比三连跳还高），方圆 20 米的物体一并震飞——路过的牛和狼挨一记重的。",
		"quip": "一个破号角。看起来吹了就会出事。",
	},
	"rewind": {
		"name": "时光回闪",
		"glyph": "时",
		"color": Color(0.3, 0.8, 0.9),
		"desc": "使用后回到 5 秒前的位置和状态。掉坑专用，悔棋神器。",
		"quip": "一个沙漏，沙子在网上倒流。",
	},
	"bomb": {
		"name": "笨笨炸弹",
		"color": Color(0.65, 0.45, 0.25),
		"desc": "扔出去后范围慢动作 + 物理痉挛 3 秒，附近的牛和狼还会挨一记轻的。杀伤力：有，但笨。",
		"quip": "一枚带着笑脸的……你确定要捡吗。",
	},
	"whistle": {
		"name": "伙伴哨子",
		"glyph": "哨",
		"color": Color(0.92, 0.92, 0.95),
		"desc": "吹响后召唤一只随机野生生物跟着你。它可能会卡墙——正好帮你看清 Bug 位置。",
		"quip": "一根简陋的骨哨。吹的时候请对它好一点。",
	},
	"wolf_tooth": {
		"name": "狼牙",
		"glyph": "牙",
		"color": Color(0.92, 0.92, 0.9),
		"desc": "捏碎 1 颗：下次被秒杀时免死，并把凶手（往往是狼）震晕。一次性护身符。",
		"quip": "一颗狼牙。白得很干净，像骨折一样干净。",
	},
	"wolf_skin": {
		"name": "狼皮",
		"glyph": "皮",
		"color": Color(0.35, 0.3, 0.32),
		"desc": "披上后 3 分钟狼不主动咬你——它们会绕着你转圈，像一群心怀鬼胎的粉丝。",
		"quip": "一张灰扑扑的狼皮。味道可疑，保暖性存疑。",
	},
	"wolf_bone": {
		"name": "狼骨粉",
		"glyph": "骨",
		"color": Color(0.8, 0.76, 0.62),
		"desc": "撒在身上：狂暴角 60 秒——角变黑变大，冲撞伤害翻倍，撞完自己转圈晕 1 秒。",
		"quip": "一小包骨粉。有点呛。",
	},
}


static func name_of(id: String) -> String:
	return str(INFO.get(id, {}).get("name", "不明物体"))


static func glyph_of(id: String) -> String:
	return str(INFO.get(id, {}).get("glyph", "?"))


static func color_of(id: String) -> Color:
	return INFO.get(id, {}).get("color", Color.WHITE) as Color


static func quip_of(id: String) -> String:
	return str(INFO.get(id, {}).get("quip", "你捡到了一个东西。"))


static func is_valid(id: String) -> bool:
	return IDS.has(id)


## 草堆随机刷道具（哨子除外——那是身份的象征）
static func random_pile_id(rng: RandomNumberGenerator) -> String:
	return PILE_IDS[rng.randi() % PILE_IDS.size()]
