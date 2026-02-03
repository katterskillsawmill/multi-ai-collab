#!/usr/bin/env node
/**
 * MCP Server: AI Orchestrator
 *
 * Provides Claude Code with tools to call other AI models:
 * - Gemini for security/docs review
 * - Codex/GPT-4 for code quality
 * - Grok for edge cases
 *
 * Usage:
 * 1. Add to claude_desktop_config.json or .mcp.json
 * 2. Configure API keys as environment variables
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const server = new Server(
  {
    name: "ai-orchestrator",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Tool definitions
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "ask_gemini",
        description: "Ask Google Gemini for code review or analysis. Good for security and documentation review.",
        inputSchema: {
          type: "object",
          properties: {
            prompt: {
              type: "string",
              description: "The prompt to send to Gemini"
            },
            code: {
              type: "string",
              description: "Optional code context to include"
            }
          },
          required: ["prompt"]
        }
      },
      {
        name: "ask_gpt4",
        description: "Ask GPT-4/Codex for code review. Good for code quality and best practices.",
        inputSchema: {
          type: "object",
          properties: {
            prompt: {
              type: "string",
              description: "The prompt to send to GPT-4"
            },
            code: {
              type: "string",
              description: "Optional code context to include"
            }
          },
          required: ["prompt"]
        }
      },
      {
        name: "ask_grok",
        description: "Ask Grok for creative analysis. Good for edge cases and unconventional insights.",
        inputSchema: {
          type: "object",
          properties: {
            prompt: {
              type: "string",
              description: "The prompt to send to Grok"
            },
            code: {
              type: "string",
              description: "Optional code context to include"
            }
          },
          required: ["prompt"]
        }
      },
      {
        name: "multi_ai_review",
        description: "Get code review from all AI models in parallel",
        inputSchema: {
          type: "object",
          properties: {
            code: {
              type: "string",
              description: "Code to review"
            },
            focus: {
              type: "string",
              description: "What to focus on: architecture, security, quality, or all",
              enum: ["architecture", "security", "quality", "all"]
            }
          },
          required: ["code"]
        }
      }
    ]
  };
});

// Helper functions for API calls
async function callGemini(prompt, code) {
  const apiKey = process.env.GOOGLE_API_KEY;
  if (!apiKey) return { error: "GOOGLE_API_KEY not set" };

  const fullPrompt = code ? `${prompt}\n\nCode:\n${code}` : prompt;

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: fullPrompt }] }],
        generationConfig: { maxOutputTokens: 2000 }
      })
    }
  );

  const data = await response.json();
  return data.candidates?.[0]?.content?.parts?.[0]?.text || "No response";
}

async function callGPT4(prompt, code) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return { error: "OPENAI_API_KEY not set" };

  const fullPrompt = code ? `${prompt}\n\nCode:\n${code}` : prompt;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: "gpt-4-turbo-preview",
      max_tokens: 2000,
      messages: [
        { role: "system", content: "You are an expert code reviewer." },
        { role: "user", content: fullPrompt }
      ]
    })
  });

  const data = await response.json();
  return data.choices?.[0]?.message?.content || "No response";
}

async function callGrok(prompt, code) {
  const apiKey = process.env.XAI_API_KEY;
  if (!apiKey) return { error: "XAI_API_KEY not set" };

  const fullPrompt = code ? `${prompt}\n\nCode:\n${code}` : prompt;

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: "grok-beta",
      max_tokens: 2000,
      messages: [
        { role: "system", content: "You are Grok. Think outside the box." },
        { role: "user", content: fullPrompt }
      ]
    })
  });

  const data = await response.json();
  return data.choices?.[0]?.message?.content || "No response";
}

// Tool handlers
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "ask_gemini": {
        const result = await callGemini(args.prompt, args.code);
        return { content: [{ type: "text", text: result }] };
      }

      case "ask_gpt4": {
        const result = await callGPT4(args.prompt, args.code);
        return { content: [{ type: "text", text: result }] };
      }

      case "ask_grok": {
        const result = await callGrok(args.prompt, args.code);
        return { content: [{ type: "text", text: result }] };
      }

      case "multi_ai_review": {
        const focus = args.focus || "all";
        const prompts = {
          architecture: "Review for architectural concerns, design patterns, and scalability.",
          security: "Review for security vulnerabilities, input validation, and data exposure.",
          quality: "Review for code quality, best practices, and potential bugs.",
          all: "Provide a comprehensive code review."
        };

        // Run in parallel
        const [gemini, gpt4, grok] = await Promise.all([
          callGemini(`${prompts[focus]} Focus on documentation and security.`, args.code),
          callGPT4(`${prompts[focus]} Focus on code quality and best practices.`, args.code),
          callGrok(`${prompts[focus]} Find edge cases and unconventional issues.`, args.code)
        ]);

        const result = `
## Gemini (Security & Docs)
${gemini}

## GPT-4 (Code Quality)
${gpt4}

## Grok (Edge Cases)
${grok}
`;
        return { content: [{ type: "text", text: result }] };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}` }],
      isError: true
    };
  }
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
