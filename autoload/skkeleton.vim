" denops 版 skkeleton の Vim script API との互換レイヤー
" 実体は全て lua/skkelua/ 以下にある

function! skkeleton#mode() abort
  return luaeval('require("skkelua").mode()')
endfunction

function! skkeleton#is_enabled() abort
  return luaeval('require("skkelua").is_enabled()')
endfunction

function! skkeleton#get_default_mapped_keys() abort
  return luaeval('require("skkelua").get_default_mapped_keys()')
endfunction

function! skkeleton#map() abort
  call luaeval('require("skkelua").map()')
endfunction

function! skkeleton#handle(func, opts) abort
  return luaeval('require("skkelua").handle(_A[1], _A[2])', [a:func, a:opts])
endfunction

function! skkeleton#config(config) abort
  call luaeval('require("skkelua").config(_A)', a:config)
endfunction

function! skkeleton#register_keymap(state, key, func_name) abort
  call luaeval('require("skkelua").register_keymap(_A[1], _A[2], _A[3])',
        \ [a:state, a:key, a:func_name])
endfunction

function! skkeleton#register_kanatable(table_name, table, create=v:false) abort
  call luaeval('require("skkelua").register_kanatable(_A[1], _A[2], _A[3])',
        \ [a:table_name, a:table, a:create])
endfunction

function! skkeleton#register_kanatable_file(table_name, path, encoding='', create=v:false) abort
  call luaeval('require("skkelua").register_kanatable_file(_A[1], _A[2], _A[3], _A[4])',
        \ [a:table_name, a:path, a:encoding, a:create])
endfunction

function! skkeleton#initialize() abort
  call luaeval('require("skkelua").initialize()')
endfunction

function! skkeleton#disable() abort
  call luaeval('require("skkelua").disable_impl()')
endfunction

function! skkeleton#get_config() abort
  return luaeval('require("skkelua").get_config()')
endfunction

function! skkeleton#vim_status() abort
  return luaeval('require("skkelua").vim_status()')
endfunction

function! skkeleton#dangerously_clear_buffer_local_mappings() abort
  call luaeval('require("skkelua").dangerously_clear_buffer_local_mappings()')
endfunction

function! skkeleton#update_database(path, ...) abort
  call luaeval('require("skkelua").update_database()')
endfunction
