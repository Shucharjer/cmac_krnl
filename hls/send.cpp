#include <ap_axi_sdata.h>
#include <ap_int.h>
#include <hls_stream.h>

using axi_t = ap_axiu<512, 0, 0, 0>;

extern "C" {

void send(unsigned char *mem, unsigned int length, hls::stream<axi_t> &out) {
#pragma HLS INTERFACE m_axi port = mem
#pragma HLS INTERFACE s_axilite port = length
#pragma HLS INTERFACE axis port = out

  axi_t tmp;

outer_loop:
  for (unsigned int i = 0; i < length; i += 64) {
    tmp.keep = 0;

  inner_loop:
    for (ap_uint<7> j = 0; j < 64; ++j) {
#pragma HLS UNROLL factor = 64
      tmp.data((j << 3) + 7, j << 3) = mem[i + j];
      tmp.keep[j] = 1;
    }
    tmp.strb = tmp.keep;
    tmp.last = (i + 64 >= length) ? 1 : 0;

    out.write(tmp);
  }
}
}
