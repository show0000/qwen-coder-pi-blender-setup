-- Local Qwen integration for lazy.nvim (drop into lua/plugins/local-ai.lua).
--   inline completion : minuet-ai.nvim  → llama-server http://127.0.0.1:8080  (qwen3-coder-next)
--   chat / inline edit: codecompanion   → same server, OpenAI-compatible
--   agent             : pi in a terminal split (<leader>ap), vision via `vision-describe`
-- Everything stays on the machine; no API keys. Disable with :Minuet / :CodeCompanionChat toggles.
local BASE = os.getenv("QWEN_BASE_URL") or "http://127.0.0.1:8080"
local MODEL = os.getenv("QWEN_MODEL_ID") or "qwen3-coder-next"

return {
  -- -------- inline completion (FIM via llama.cpp /infill when supported, else chat) ----------
  {
    "milanglacier/minuet-ai.nvim",
    event = "InsertEnter",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      provider = "openai_fim_compatible",
      n_completions = 1,
      context_window = 8000,          -- chars sent around the cursor; keep small for a local model
      throttle = 1200,
      debounce = 400,
      request_timeout = 6,
      virtualtext = {
        auto_trigger_ft = { "*" },
        keymap = { accept = "<A-a>", accept_line = "<A-l>", next = "<A-]>", prev = "<A-[>", dismiss = "<A-e>" },
      },
      provider_options = {
        openai_fim_compatible = {
          api_key = "TERM",             -- any non-empty env var name; server ignores it
          name = "llama.cpp",
          end_point = BASE .. "/v1/completions",
          model = MODEL,
          optional = { max_tokens = 96, top_p = 0.9, stop = { "\n\n" } },
          -- llama.cpp FIM template for Qwen coders
          template = {
            prompt = function(ctx_before, ctx_after) return "<|fim_prefix|>" .. ctx_before .. "<|fim_suffix|>" .. ctx_after .. "<|fim_middle|>" end,
            suffix = false,
          },
        },
      },
    },
  },

  -- -------- chat + inline edit ---------------------------------------------------------------
  {
    "olimorris/codecompanion.nvim",
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
    keys = {
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "AI chat (local qwen)" },
      { "<leader>ae", ":CodeCompanion ", mode = "v", desc = "AI inline edit selection" },
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "AI actions" },
    },
    dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
    opts = {
      adapters = {
        qwen = function()
          return require("codecompanion.adapters").extend("openai_compatible", {
            name = "qwen",
            env = { url = BASE, api_key = "local", chat_url = "/v1/chat/completions" },
            schema = {
              model = { default = MODEL },
              temperature = { default = 0.7 },
              max_tokens = { default = 4096 },
            },
          })
        end,
      },
      strategies = {
        chat = { adapter = "qwen" },
        inline = { adapter = "qwen" },
      },
      display = { chat = { show_settings = false } },
    },
  },

  -- -------- pi agent in a split --------------------------------------------------------------
  {
    "akinsho/toggleterm.nvim",
    keys = {
      { "<leader>ap", function()
          local Terminal = require("toggleterm.terminal").Terminal
          _G.__pi_term = _G.__pi_term or Terminal:new({ cmd = "qwen pi", direction = "vertical", size = 100, close_on_exit = false, hidden = true })
          _G.__pi_term:toggle()
        end, desc = "pi agent (local qwen)" },
    },
    opts = { shade_terminals = false },
  },
}
