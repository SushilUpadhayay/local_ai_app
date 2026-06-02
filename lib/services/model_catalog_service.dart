import '../models/model_item.dart';

class ModelCatalogService {
  // Returns the list of default/available models with advanced metadata.
  // In the future, this can query remote Hugging Face API or local storage.
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
        url: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 4096, // Configured context size for mobile
        modelFamily: 'Qwen',
      ),
      ModelItem(
        id: 'qwen-1.5b',
        name: 'Qwen 1.5B',
        fullName: 'Qwen 2.5 1.5B Instruct (Q4_K_M)',
        size: '1.2 GB',
        ram: 'Needs 6GB+ RAM',
        status: 'available',
        active: false,
        category: 'Reasoning',
        url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 4096,
        modelFamily: 'Qwen',
      ),
      ModelItem(
        id: 'gemma-2b',
        name: 'Gemma 2B',
        fullName: 'Gemma 2 2B IT (Q4_K_M)',
        size: '1.6 GB',
        ram: 'Needs 8GB+ RAM',
        status: 'available',
        active: false,
        category: 'Advanced Text',
        url: 'https://huggingface.co/lmstudio-community/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
        quantization: 'Q4_K_M',
        contextWindow: 4096,
        modelFamily: 'Gemma',
      ),
    ];
  }
}
