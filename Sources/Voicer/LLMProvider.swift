import Foundation

struct LLMProvider: Equatable {
    let name: String
    let baseURL: String
    let defaultModel: String
    let supportsSpeech: Bool

    static let all: [LLMProvider] = [
        LLMProvider(name: "OpenAI", baseURL: "https://api.openai.com", defaultModel: "gpt-4o-mini", supportsSpeech: true),
        LLMProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", defaultModel: "deepseek-chat", supportsSpeech: false),
        LLMProvider(name: "Moonshot (Kimi)", baseURL: "https://api.moonshot.cn", defaultModel: "moonshot-v1-8k", supportsSpeech: false),
        LLMProvider(name: "智谱 AI (GLM)", baseURL: "https://open.bigmodel.cn/api/paas", defaultModel: "glm-4-flash", supportsSpeech: false),
        LLMProvider(name: "Alibaba (通义千问)", baseURL: "https://dashscope.aliyuncs.com/compatible-mode", defaultModel: "qwen-turbo", supportsSpeech: false),
        LLMProvider(name: "零一万物 (01.AI)", baseURL: "https://api.lingyiwanwu.com", defaultModel: "yi-lightning", supportsSpeech: false),
        LLMProvider(name: "阶跃星辰 (StepFun)", baseURL: "https://api.stepfun.com", defaultModel: "step-1-8k", supportsSpeech: false),
        LLMProvider(name: "Groq", baseURL: "https://api.groq.com/openai", defaultModel: "llama-3.1-8b-instant", supportsSpeech: true),
        LLMProvider(name: "xAI (Grok)", baseURL: "https://api.x.ai", defaultModel: "grok-3-mini", supportsSpeech: false),
        LLMProvider(name: "Mistral AI", baseURL: "https://api.mistral.ai", defaultModel: "mistral-small-latest", supportsSpeech: true),
        LLMProvider(name: "Fireworks AI", baseURL: "https://api.fireworks.ai/inference", defaultModel: "accounts/fireworks/models/llama-v3p1-8b", supportsSpeech: true),
        LLMProvider(name: "SiliconFlow", baseURL: "https://api.siliconflow.cn", defaultModel: "Qwen/Qwen2.5-7B-Instruct", supportsSpeech: true),
        LLMProvider(name: "Perplexity", baseURL: "https://api.perplexity.ai", defaultModel: "sonar", supportsSpeech: false),
        LLMProvider(name: "MiniMax (海螺)", baseURL: "https://api.minimaxi.com", defaultModel: "MiniMax-M2.1", supportsSpeech: false),
        LLMProvider(name: "Custom", baseURL: "", defaultModel: "", supportsSpeech: false),
    ]

    static func provider(named name: String) -> LLMProvider {
        all.first { $0.name == name } ?? all[0]
    }
}