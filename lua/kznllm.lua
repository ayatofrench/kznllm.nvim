local utils = require 'kznllm.utils'
local M = {}
local api = vim.api

if vim.fn.executable 'minijinja-cli' ~= 1 then
  error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
end

-- Specify the path where you want to save the file
M.CACHE_DIRECTORY = vim.fn.stdpath 'cache' .. '/kznllm/history/'

local success, error_message

success, error_message = os.execute('mkdir -p "' .. M.CACHE_DIRECTORY .. '"')
if not success then
  print('Error creating directory: ' .. error_message)
  return
end

-- Global variable to store the buffer number
local input_buf_nr = nil
local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

--- Invokes an LLM via a supported API spec in "buffer" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { system_prompt_template?: string, user_prompt_template: string }
---@param make_job_fn function
function M.invoke_llm_buffer_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = utils.get_visual_selection()

  if opts.user_prompt_template == nil then
    opts.user_prompt_template = 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  end

  local user_input = nil
  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      user_input = input
    end
  end)

  if user_input == nil then
    return
  end

  local user_prompt_args = {
    supporting_context = visual_selection,
    user_query = user_input,
  }

  -- after getting lines, exit visual mode and go to end of the current line
  api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
  api.nvim_feedkeys('$', 'nx', false)

  local rendered_messages = {
    system_message = nil,
    user_messages = {},
  }

  if opts.system_prompt_template ~= nil then
    rendered_messages.system_message = utils.make_prompt_from_template(opts.system_prompt_template, user_prompt_args)
  end

  if opts.user_prompt_template ~= nil then
    local rendered_prompt = utils.make_prompt_from_template(opts.user_prompt_template, user_prompt_args)
    table.insert(rendered_messages.user_messages, rendered_prompt)
  end

  -- if buffer is already open, make job from full buffer
  if input_buf_nr and api.nvim_buf_is_valid(input_buf_nr) then
    api.nvim_set_current_buf(input_buf_nr)
    -- clear the buffer before proceeding
    api.nvim_buf_set_lines(input_buf_nr, 0, -1, false, {})
  else
    local filepath = M.CACHE_DIRECTORY .. tostring(os.time()) .. '.txt'
    local cur_buf = api.nvim_get_current_buf()
    input_buf_nr = utils.create_input_buffer(cur_buf, filepath, rendered_messages)
    -- Set up autocmd to clear the buffer number when it's deleted
    api.nvim_create_autocmd('BufDelete', {
      buffer = input_buf_nr,
      callback = function()
        input_buf_nr = nil
      end,
    })
  end

  local active_job = make_job_fn(rendered_messages, utils.write_content_at_end)
  active_job:start()
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LLM_Escape',
    callback = function()
      if active_job.is_shutdown ~= true then
        active_job:shutdown()
        print 'LLM streaming cancelled'
      end
    end,
  })
end

--- Invokes an LLM via a supported API spec in "replace" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { system_prompt_template?: string, user_prompt_template?: string }
---@param make_job_fn function
function M.invoke_llm_replace_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = utils.get_visual_selection()

  local user_prompt_args = { code_snippet = visual_selection }

  if opts.system_prompt_template == nil then
    opts.system_prompt_template = 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  end

  local rendered_messages = {
    system_message = nil,
    user_messages = {},
  }

  if opts.system_prompt_template ~= nil then
    rendered_messages.system_message = utils.make_prompt_from_template(opts.system_prompt_template, user_prompt_args)
  end

  if opts.user_prompt_template ~= nil then
    local rendered_prompt = utils.make_prompt_from_template(opts.user_prompt_template, user_prompt_args)
    table.insert(rendered_messages.user_messages, rendered_prompt)
  end

  api.nvim_feedkeys('c', 'nx', false)

  local active_job = make_job_fn(rendered_messages, utils.write_content_at_cursor)
  active_job:start()
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LLM_Escape',
    callback = function()
      if active_job.is_shutdown ~= true then
        active_job:shutdown()
        print 'LLM streaming cancelled'
      end
    end,
  })
end

api.nvim_set_keymap('n', '<Esc>', '', {
  noremap = true,
  silent = true,
  callback = function()
    api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
  end,
})

return M
