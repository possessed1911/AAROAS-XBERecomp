#pragma once
#include <mutex>

#include "gpu/state.h"

namespace d3d {

gpu::State& State();
std::recursive_mutex& Lock();
uint32_t Buffer(uint32_t index) noexcept;
uint32_t BufferCount() noexcept;

}  // namespace d3d
