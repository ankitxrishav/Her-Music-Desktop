#ifndef RUNNER_WASAPI_CHANNEL_H_
#define RUNNER_WASAPI_CHANNEL_H_

#include <flutter/binary_messenger.h>

#include <memory>

namespace her_music {

class WasapiChannel {
 public:
  explicit WasapiChannel(flutter::BinaryMessenger* messenger);
  ~WasapiChannel();

  WasapiChannel(const WasapiChannel&) = delete;
  WasapiChannel& operator=(const WasapiChannel&) = delete;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace her_music

#endif  // RUNNER_WASAPI_CHANNEL_H_
