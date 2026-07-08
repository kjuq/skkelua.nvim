# skkelua

Neovim 専用の SKK 日本語入力環境です。pure Lua で実装されており、
Neovim 組み込みの Lua ランタイムだけで動作します。

[skkeleton](https://github.com/vim-skk/skkeleton) (denops/Deno 製) を参考に
作られた独立のプラグインで、モードインジケータも内蔵しています。

## Requirements

- Neovim 0.10+
- (任意) `google_japanese_input` ソースを使う場合は `curl`

denops.vim / Deno は不要です。

## Installation

任意のプラグインマネージャで導入できます。

```lua
-- lazy.nvim
{
	"kjuq/skkelua.nvim",
	config = function()
		require("skkelua").config({
			globalDictionaries = { "~/.skk/SKK-JISYO.L" },
		})
		vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkelua-toggle)")
	end,
}
```

## Usage

`<Plug>(skkelua-enable)` / `<Plug>(skkelua-disable)` / `<Plug>(skkelua-toggle)` を
insert / cmdline / terminal モードにマップして使います。

```lua
vim.keymap.set({ "i", "c", "t" }, "<C-j>", "<Plug>(skkelua-toggle)")
```

設定は Lua API で行います。

```lua
require("skkelua").config({
	globalDictionaries = {
		"~/.skk/SKK-JISYO.L",              -- エンコーディング自動判定
		{ "~/.skk/SKK-JISYO.geo", "euc-jp" }, -- 明示指定
	},
	eggLikeNewline = true,
	registerConvertResult = true,
})
```

ユーザー辞書はデフォルトで `stdpath("data")/skkelua/jisyo`
(通常 `~/.local/share/nvim/skkelua/jisyo`) に保存されます。

現在の状態は Lua API で参照できます。

```lua
require("skkelua").is_enabled() -- 有効かどうか
require("skkelua").mode()       -- "hira" / "kata" / "hankata" / "zenkaku" / "abbrev" / ""
require("skkelua").phase()      -- "input" / "input:okurinasi" / "input:okuriari" / "henkan" / ...
```

詳細は [doc/skkelua.txt](doc/skkelua.txt) を参照してください。

## モードインジケータ

カーソル付近に現在の入力モード (ひら/カタ/英字など) をフローティング表示する
インジケータを内蔵しています。デフォルトで有効です。

```lua
require("skkelua").config({
	indicator = {
		enabled = true,       -- false で無効化
		alwaysShown = false,  -- skkelua が有効な間だけ表示
		fadeOutMs = 0,        -- 0 で自動フェードアウトなし
		hiraText = "ひら",    -- 表示テキストのカスタマイズ
	},
})
```

ハイライトは `SkkeluaIndicatorHira` などのグループで上書きできます。

## 変換候補の補完表示 (builtin LSP)

変換入力中 (▽かんじ) の候補を、Neovim 組み込みの補完メニューに自動表示できます。
in-process の LSP サーバーとして実装されており、外部プロセスは起動しません。

```lua
require("skkelua").config({
	completion = { enabled = true },
})
```

- ▽ に続けてかなを打つと、見出しを前方一致検索した変換候補が pum に出ます
- 送りあり変換の入力中 (▽おく*r) も、送りのローマ字からありうる送り仮名を
  展開した完成形 (送り/送る/送れ...) が候補に出ます
- 候補選択中 (▼送る) も全候補が pum に出るので、pum から選び直せます
- `<C-n>`/`<C-p>` で選択し、`<C-y>` で確定すると pre-edit 全体が候補に置き換わり、
  選んだ候補はユーザー辞書へ登録されます (次回から優先されます)
- skkelua の有効・無効に連動して補完も付いたり外れたりします

## skkeleton との関係

skkelua は [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton) の
TypeScript 実装を参考に Lua で書かれた別のプラグインです。
変換エンジンの挙動・辞書形式・設定オプション名の多くは skkeleton を踏襲していますが、
API 互換はありません (`skkeleton#*` 関数や `g:skkeleton#*` 変数は提供しません)。

denops 版との主な違い:

| 項目 | skkeleton | skkelua |
|---|---|---|
| ランタイム | Deno + denops.vim | Neovim 組み込み Lua のみ |
| 対応エディタ | Vim / Neovim | Neovim 0.10+ のみ |
| 設定 API | `skkeleton#config()` | `require("skkelua").config()` |
| モードインジケータ | 別プラグイン (skkeleton_indicator.nvim) | 内蔵 |
| ユーザー辞書デフォルト | `~/.skkeleton` | `stdpath("data")/skkelua/jisyo` |
| 辞書ロード | 非同期 | 同期 (SKK-JISYO.L 規模で数百 ms、初回のみ) |
| 辞書形式 | SKK/JSON/YAML/msgpack/Deno KV | SKK/JSON/msgpack |
| SKK サーバー | 非同期 TCP | 同期 TCP (タイムアウト 1 秒) |
| Google 日本語入力 | fetch | curl |
| ddc.vim ソース | 同梱 | 非同梱 (補完用 Lua API を提供) |

## Development

```sh
# テスト実行
nvim --clean --headless -l tests/run.lua

# 特定の spec のみ
nvim --clean --headless -l tests/run.lua henkan

# 普段の設定と切り離して手元で試す
nvim -u tests/minimal_init.lua
```

## License

zlib license

## Credits

- 変換エンジンは [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton)
  (Copyright (c) 2021 kuuote, zlib license) の TypeScript 実装を Lua に移植したものです
- モードインジケータは
  [delphinus/skkeleton_indicator.nvim](https://github.com/delphinus/skkeleton_indicator.nvim)
  (Copyright (c) 2021 Yasushi Jinnouchi, zlib license) を基に内蔵化したものです
