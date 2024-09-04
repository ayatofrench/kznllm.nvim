local kznllm = require 'kznllm'
local Path = require 'plenary.path'

local M = {}

local API_KEY_NAME = 'GROQ_API_KEY'
local URL = 'https://api.groq.com/openai/v1/chat/completions'

local TEMPLATE_PATH = vim.fn.expand(vim.fn.stdpath 'data') .. '/lazy/kznllm.nvim'

M.MODELS = {
  LLAMA_3_1_405B = { name = 'llama-3.1-405b-reasoning', max_tokens = 131072 },
  LLAMA_3_1_70B = { name = 'llama-3.1-70b-versatile', max_tokens = 131072 },
  LLAMA_3_70B = { name = 'llama3-70b-8192', max_tokens = 8192 },
}

M.MESSAGE_TEMPLATES = {

  FILL_MODE_SYSTEM_PROMPT = 'nous_research/fill_mode_system_prompt.xml.jinja',
  FILL_MODE_USER_PROMPT = 'nous_research/fill_mode_user_prompt.xml.jinja',

  NOUS_RESEARCH = {
    FILL_MODE_SYSTEM_PROMPT = 'nous_research/fill_mode_system_prompt.xml.jinja',
    FILL_MODE_USER_PROMPT = 'nous_research/fill_mode_user_prompt.xml.jinja',
  },

  GROQ = {
    --- this prompt has to be written to output valid code
    FILL_MODE_SYSTEM_PROMPT = 'groq/fill_mode_system_prompt.xml.jinja',
    FILL_MODE_USER_PROMPT = 'groq/fill_mode_user_prompt.xml.jinja',
  },
}

local API_ERROR_MESSAGE = [[
ERROR: api key name is set to %s and is missing from your environment variables.

Load somewhere safely from config `export %s=<api_key>`]]

local Job = require 'plenary.job'

--- Constructs arguments for constructing an HTTP request to the OpenAI API
--- using cURL.
---
---@param data table
---@return string[]
function M.make_curl_args(data, opts)
  local url = opts and opts.url or URL
  local api_key = os.getenv(opts and opts.api_key_name or API_KEY_NAME)

  if not api_key then
    error(API_ERROR_MESSAGE:format(API_KEY_NAME, API_KEY_NAME), 1)
  end

  local args = {
    '-s', --silent
    '-N', --no buffer
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    '-d',
    vim.json.encode(data),
    '-H',
    'Authorization: Bearer ' .. api_key,
    url,
  }

  return args
end

--- Process server-sent events based on OpenAI spec
--- [See Documentation](https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream)
---
---@param out string
---@return string
local function handle_data(out)
  -- based on sse spec (OpenAI spec uses data-only server-sent events)
  local data, data_epos
  _, data_epos = string.find(out, '^data: ')

  if data_epos then
    data = string.sub(out, data_epos + 1)
  end

  local content = ''

  if data and data:match '"delta":' then
    local json = vim.json.decode(data)
    if json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content then
      content = json.choices[1].delta.content
    else
      vim.print(data)
    end
  end

  return content
end

---@param args table
---@param writer_fn fun(content: string)
function M.make_job(args, writer_fn, on_exit_fn)
  local active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      local content = handle_data(out)
      if content and content ~= nil then
        vim.schedule(function()
          writer_fn(content)
        end)
      end
    end,
    on_stderr = function(message, _)
      error(message, 1)
    end,
    on_exit = function()
      vim.schedule(function()
        on_exit_fn()
      end)
    end,
  }
  return active_job
end

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for groq spec
---@param prompt_args any
---@param opts any
---@return table
function M.make_data_for_chat(prompt_args, opts)
  local template_path = Path:new(opts and opts.template_path or TEMPLATE_PATH)
  local messages = {
    {
      role = 'system',
      content = kznllm.make_prompt_from_template(template_path / M.MESSAGE_TEMPLATES.FILL_MODE_SYSTEM_PROMPT, prompt_args),
    },
    {
      role = 'user',
      content = kznllm.make_prompt_from_template(template_path / M.MESSAGE_TEMPLATES.FILL_MODE_USER_PROMPT, prompt_args),
    },
  }

  local data = {
    messages = messages,
    model = M.MODELS.LLAMA_3_1_70B.name,
    temperature = 0.7,
    stream = true,
  }

  return data
end

return M
