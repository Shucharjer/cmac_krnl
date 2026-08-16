#include <ap_axi_sdata.h>
#include <ap_int.h>
#include <hls_stream.h>

using axi_t = ap_axiu<512, 0, 0, 0>;

extern "C" {

void recv(unsigned char *mem, unsigned int &length, hls::stream<axi_t> &in) {
#pragma HLS INTERFACE axis port = in
#pragma HLS INTERFACE m_axi port = mem offset = slave bundle = gmem
#pragma HLS INTERFACE s_axilite port = mem bundle = control
#pragma HLS INTERFACE s_axilite port = length bundle = control
#pragma HLS INTERFACE s_axilite port = return bundle = control

  axi_t tmp;
  unsigned int local_length = 0;
  tmp.last = 0;

  while (!tmp.last) {
    in.read(tmp);

    ap_uint<7> beat_bytes = 0;
    for (ap_uint<7> i = 0; i < 64; ++i) {
#pragma HLS UNROLL factor = 64
      if (tmp.keep[i]) {
        mem[local_length + i] = tmp.data((i << 3) + 7, i << 3);
        beat_bytes = i + 1;
      }
    }
    local_length += beat_bytes;
  }
  length = local_length;
}
}
