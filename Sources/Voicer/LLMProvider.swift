import Foundation

struct LLMProvider: Equatable {
    let name: String
    let baseURL: String
    let defaultModel: String

    static let all: [LLMProvider] = [
        LLMProvider(name: "OpenAI", baseURL: "https://api.openai.com", defaultModel: "gpt-4o-mini"),
        LLMProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        LLMProvider(name: "Moonshot (Kimi)", baseURL: "https://api.moonshot.cn", defaultModel: "moonshot-v1-8k"),
        LLMProvider(name: "智谱 AI (GLM)", baseURL: "https://open.bigmodel.cn/api/paas", defaultModel: "glm-4-flash"),
        LLMProvider(name: "ByteDance (豆包)", baseURL: "https://ark.cn-beijing.volces.com/api", defaultModel: "doubao-lite-4k"),
        LLMProvider(name: "Alibaba (通义千问)", baseURL: "https://dashscope.aliyuncs.com/compatible-mode", defaultModel: "qwen-turbo"),
        LLMProvider(name: "Baichuan (百川)", baseURL: "https://api.baichuan-ai.com", defaultModel: "Baichuan4"),
        LLMProvider(name: "MiniMax", baseURL: "https://api.minimax.chat", defaultModel: "abab6.5s-chat"),
        LLMProvider(name: "零一万物 (01.AI)", baseURL: "https://api.lingyiwanwu.com", defaultModel: "yi-lightning"),
        LLMProvider(name: "阶跃星辰 (StepFun)", baseURL: "https://api.stepfun.com", defaultModel: "step-1-8k"),
        LLMProvider(name: "Groq", baseURL: "https://api.groq.com/openai", defaultModel: "llama-3.1-8b"),
        LLMProvider(name: "xAI (Grok)", baseURL: "https://api.x.ai", defaultModel: "grok-2"),
        LLMProvider(name: "Mistral AI", baseURL: "https://api.mistral.ai", defaultModel: "mistral-small"),
        LLMProvider(name: "Cohere", baseURL: "https://api.cohere.ai", defaultModel: "command-r"),
        LLMProvider(name: "Perplexity", baseURL: "https://api.perplexity.ai", defaultModel: "llama-3.1-sonar-small"),
        LLMProvider(name: "Fireworks AI", baseURL: "https://api.fireworks.ai/inference", defaultModel: "accounts/fireworks/models/llama-v3p1-8b"),
        LLMProvider(name: "SiliconFlow", baseURL: "https://api.siliconflow.cn", defaultModel: "Qwen/Qwen2.5-7B-Instruct"),
        LLMProvider(name: "Custom", baseURL: "", defaultModel: ""),
    ]

    static func provider(named name: String) -> LLMProvider {
        all.first { $0.name == name } ?? all[0]
    }
}
