#include "cmac.hpp"
#include <xrt/experimental/xrt_ip.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>

int main() {
  auto device = xrt::device(0);
  std::cout << "found device:\n";
  std::cout << device.get_info<xrt::info::device::name>() << '\n';

  std::cout << "load xclbin...\n";
  auto uuid = device.load_xclbin("build/cmac_krnl.hw.au50.xclbin");
  std::cout << "succeeded\n";

  cmac cmac(xrt::ip(device, uuid, "cmac_au50"));
  std::cout << "found cmac instance\n";

  return 0;
}