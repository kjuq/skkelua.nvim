# skkelua

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
	"you/skkelua",
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
	userDictionary = "~/.skkeleton",
	eggLikeNewline = true,
	registerConvertResult = true,
})
```

詳細は [doc/skkelua.txt](doc/skkelua.txt) を参照してください。

## skkeleton 互換

denops 版 skkeleton からの移行と周辺プラグインとの連携のため、
ユーザーに見えるインターフェイスは skkeleton の名前を維持しています。

- Vim script 関数: `skkeleton#config()` / `skkeleton#register_kanatable()` /
  `skkeleton#register_keymap()` / `skkeleton#handle()` など (autoload/skkeleton.vim)
- グローバル変数: `g:skkeleton#enabled` / `g:skkeleton#mode` / `g:skkeleton#state` /
  `g:skkeleton#mapped_keys`
- autocmd: `User skkeleton-enable-pre/post` / `skkeleton-disable-pre/post` /
  `skkeleton-mode-changed` / `skkeleton-handled` など
- `<Plug>(skkeleton-enable/disable/toggle)` (互換エイリアス。正式名は `<Plug>(skkelua-*)`)
- ユーザー辞書のデフォルトパス `~/.skkeleton` (denops 版の辞書をそのまま引き継げます)

このため [skkeleton_indicator.nvim](https://github.com/delphinus/skkeleton_indicator.nvim)
などの周辺プラグインや、denops 版向けの既存設定の多くはそのまま動きます。

```vim
" denops 版向けの設定がそのまま動く例
call skkeleton#config({ 'globalDictionaries': ['~/.skk/SKK-JISYO.L'] })
call skkeleton#register_kanatable('rom', { 'jj': 'escape' })
imap <C-j> <Plug>(skkeleton-toggle)
```

## オリジナル (denops 版) との違い

| 項目 | denops 版 skkeleton | skkelua |
|---|---|---|
| ランタイム | Deno + denops.vim | Neovim 組み込み Lua のみ |
| 対応エディタ | Vim / Neovim | Neovim 0.10+ のみ |
| 設定 API | `skkeleton#config()` | `require("skkelua").config()` (Vim script 互換あり) |
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

# 普段の設定と切り離して手元で試す
nvim -u tests/minimal_init.lua
```

## License

zlib license (オリジナルの skkeleton に準拠)

## Credits

このプラグインは [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton) の
TypeScript 実装を Lua に移植したものです。
