# skkeleton-lua

[skkeleton](https://github.com/vim-skk/skkeleton) (denops/Deno 製の SKK 日本語入力環境) を Neovim 専用に pure Lua で書き換えたプラグインです。

denops.vim と Deno のインストールが不要になり、Neovim 組み込みの Lua ランタイムだけで動作します。

## Requirements

- Neovim 0.10+
- (任意) `google_japanese_input` ソースを使う場合は `curl`

denops.vim / Deno は不要です。

## Installation

任意のプラグインマネージャで導入できます。

```lua
-- lazy.nvim
{
	"you/skkeleton-lua",
	config = function()
		require("skkeleton").config({
			globalDictionaries = { "~/.skk/SKK-JISYO.L" },
		})
		vim.keymap.set({ "i", "c" }, "<C-j>", "<Plug>(skkeleton-toggle)")
	end,
}
```

## Usage

`<Plug>(skkeleton-enable)` / `<Plug>(skkeleton-disable)` / `<Plug>(skkeleton-toggle)` を
insert / cmdline / terminal モードにマップして使います。

```lua
vim.keymap.set({ "i", "c", "t" }, "<C-j>", "<Plug>(skkeleton-toggle)")
```

設定は Lua API で行います。

```lua
require("skkeleton").config({
	globalDictionaries = {
		"~/.skk/SKK-JISYO.L",              -- エンコーディング自動判定
		{ "~/.skk/SKK-JISYO.geo", "euc-jp" }, -- 明示指定
	},
	userDictionary = "~/.skkeleton",
	eggLikeNewline = true,
	registerConvertResult = true,
})
```

オリジナルの Vim script API (`skkeleton#config()` など) も互換レイヤーとして残しているため、
既存の設定の多くはそのまま動きます。

```vim
call skkeleton#config({ 'globalDictionaries': ['~/.skk/SKK-JISYO.L'] })
call skkeleton#register_kanatable('rom', { 'jj': 'escape' })
imap <C-j> <Plug>(skkeleton-toggle)
```

詳細は [doc/skkeleton.txt](doc/skkeleton.txt) を参照してください。

## オリジナル (denops 版) との違い

| 項目 | denops 版 | Lua 版 |
|---|---|---|
| ランタイム | Deno + denops.vim | Neovim 組み込み Lua のみ |
| 対応エディタ | Vim / Neovim | Neovim 0.10+ のみ |
| 設定 API | `skkeleton#config()` | `require("skkeleton").config()` (Vim script 互換あり) |
| 辞書ロード | 非同期 | 同期 (SKK-JISYO.L 規模で数百 ms、初回 enable 時のみ) |
| 辞書形式 | SKK/JSON/YAML/msgpack/Deno KV | SKK/JSON/msgpack (YAML と Deno KV は非対応) |
| SKK サーバー | 非同期 TCP | 同期 TCP (タイムアウト 1 秒) |
| Google 日本語入力 | fetch | curl |
| ddc.vim ソース | 同梱 | 非同梱 (補完用 API は `get_completion_result()` 等として提供) |

### 非対応の機能

- `updateDatabase` (Deno KV ベースの辞書データベース): `databasePath` 設定は受け付けますが機能しません
- YAML 辞書
- ddc.vim / ddc 連携ソース (denops 依存のため)。代わりに補完プラグイン向けの Lua API
  (`get_pre_edit()`, `get_prefix()`, `get_completion_result()`, `get_ranks()`,
  `complete_callback()`) を提供します

## Development

```sh
# テスト実行
nvim --clean --headless -l tests/run.lua

# 特定の spec のみ
nvim --clean --headless -l tests/run.lua henkan
```

## License

zlib license (オリジナルの skkeleton に準拠)

## Credits

このプラグインは [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton) の
TypeScript 実装を Lua に移植したものです。
