import '../models/model_item.dart';

class ModelCatalogService {
  // Returns the list of available models with advanced metadata.
  // maxOutputTokens is computed automatically from contextWindow — do NOT add it here.
  // Rule: 25% of contextWindow, clamped to [512, 2048]. See ModelItem.maxOutputTokens.
  //
  // To add a new model, just provide:
  //   id, name, fullName, size, ram, url, quantization, contextWindow, modelFamily
  // Output token limit is derived automatically.
  Future<List<ModelItem>> getAvailableModels() async {
    return [
      ModelItem(
        id: 'qwen-0.5b',
        name: 'Qwen 0.5B',
        fullName: 'Qwen 2.5 0.5B Instruct (Q4_K_M)',
        size: '398 MB',
        ram: 'Needs 4GB+ RAM',
        status: 'available',
        active: false,
        category: 'General Text',
        url:
            'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 2048, // Reduced from 4096: halves KV cache so it loads on 6GB phones
        modelFamily: 'Qwen',
      ),
      ModelItem(
        id: 'qwen-1.5b',
        name: 'Qwen 1.5B',
        fullName: 'Qwen 2.5 1.5B Instruct (Q4_K_M)',
        size: '1.2 GB',
        ram: 'Needs 6GB RAM',
        status: 'available',
        active: false,
        category: 'Reasoning',
        url:
            'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 4096,
        modelFamily: 'Qwen',
      ),
      ModelItem(
        id: 'gemma-2b',
        name: 'Gemma 2B',
        fullName: 'Gemma 2 2B IT (Q4_K_M)',
        size: '1.6 GB',
        ram: 'Needs 6GB+ RAM',
        status: 'available',
        active: false,
        category: 'Advanced Text',
        url:
            'https://huggingface.co/lmstudio-community/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 4096,
        modelFamily: 'Gemma',
      ),
      ModelItem(
        id: 'gemma-4-e4b',
        name: 'Gemma 4 E4B',
        fullName: 'Gemma 4 E4B Instruct (Q4_K_M)',
        size: '2.5 GB',
        ram: 'Needs 6GB RAM',
        status: 'available',
        active: false,
        category: 'Advanced Text',
        url:
            'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 4096,
        modelFamily: 'Gemma',
      ),
      ModelItem(
        id: 'qwen-3b',
        name: 'Qwen 3B',
        fullName: 'Qwen 2.5 3B Instruct (Q4_K_M)',
        size: '1.9 GB',
        ram: 'Needs 6GB RAM',
        status: 'available',
        active: false,
        category: 'Reasoning',
        url:
            'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 2048, // Reduced from 4096: halves KV cache so it loads on 6GB phones
        modelFamily: 'Qwen',
      ),
      ModelItem(
        id: 'qwen-7b',
        name: 'Qwen 7B',
        fullName: 'Qwen 2.5 7B Instruct (Q4_K_M)',
        size: '4.3 GB',
        ram: 'Needs 8GB+ RAM',
        status: 'available',
        active: false,
        category: 'Heavy Reasoning',
        url:
            'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 4096,
        modelFamily: 'Qwen',
      ),
      ModelItem(
        id: 'whisper-tiny',
        name: 'Whisper Tiny',
        fullName: 'Whisper Tiny Multilingual (GGML)',
        size: '75 MB',
        ram: 'Needs 1GB+ RAM',
        status: 'available',
        active: false,
        category: 'Speech Recognition',
        url:
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
        quantization: 'F16',
        contextWindow: 0, // → auto maxOutputTokens: 0 (audio model)
        modelFamily: 'Whisper',
      ),
      ModelItem(
        id: 'whisper-base',
        name: 'Whisper Base',
        fullName: 'Whisper Base Multilingual (GGML)',
        size: '140 MB',
        ram: 'Needs 2GB+ RAM',
        status: 'available',
        active: false,
        category: 'Speech Recognition',
        url:
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
        quantization: 'F16',
        contextWindow: 0, // → auto maxOutputTokens: 0 (audio model)
        modelFamily: 'Whisper',
      ),
      ModelItem(
        id: 'whisper-small',
        name: 'Whisper Small',
        fullName: 'Whisper Small Multilingual (GGML)',
        size: '240 MB',
        ram: 'Needs 3GB+ RAM',
        status: 'available',
        active: false,
        category: 'Speech Recognition',
        url:
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
        quantization: 'F16',
        contextWindow: 0, // → auto maxOutputTokens: 0 (audio model)
        modelFamily: 'Whisper',
      ),
    ];
  }
}
