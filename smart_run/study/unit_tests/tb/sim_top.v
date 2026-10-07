// sim_top: Verilator 용 래퍼 top. 원본 tb.v 를 수정하지 않고 study_probe / study_tbdev 를 나란히 붙인다.
// (iverilog 에서는 둘 다 별도 root 로 컴파일되므로 이 파일이 필요 없다)
`timescale 1ns/100ps
module sim_top;
  tb          tb();
  study_probe study_probe();   // 관찰 (VCD, trace, 콘솔)
  study_tbdev study_tbdev();   // TB 장치: 외부 인터럽트 선 구동
endmodule
