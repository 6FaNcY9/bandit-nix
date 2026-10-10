'use strict';

function modelRequest(api, {model, messages, sampling, think = false}) {
  if (api === 'ollama') return {model, messages, stream: false, think, options: {...sampling}};
  if (api === 'openai') {
    const options = {...sampling};
    delete options.num_ctx;
    const max_tokens = options.num_predict ?? 512;
    delete options.num_predict;
    return {model, messages, stream: false, ...options, max_tokens, chat_template_kwargs: {enable_thinking: false}};
  }
  throw new Error(`Unknown model API: ${api}`);
}

function modelReply(api, data) {
  const reply = api === 'ollama' ? data.message?.content : data.choices?.[0]?.message?.content;
  if (typeof reply !== 'string') throw new Error('model: no answer');
  return reply;
}

module.exports = {modelRequest, modelReply};
