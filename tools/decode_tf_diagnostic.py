"""Decode SDINFO without touching the card, BLE link, or hardware."""
import argparse,json,re
def decode(value):
    value=value.strip().upper()
    if value.startswith('SD '):value=value[3:]
    if not re.fullmatch(r'[0-9A-F]{16}',value):raise ValueError('需要 16 位十六进制 SDINFO 诊断码')
    d=int(value,16);extra=(d>>27)&0xffffffff
    result={'raw':value,'error':d&15,'state':(d>>4)&31,'step':(d>>9)&15,
            'command':(d>>13)&63,'response':f'{(d>>19)&255:02X}',
            'attempts_in_round':((d>>59)&3)+1,'initialized':bool(d&(1<<61))}
    if result['command']==0 and not result['initialized'] and extra>>16:
        result['pad_trace']={'manual_round_generation':extra>>16,
            'clock_level_mismatch':bool(extra&0x8000),'cs_level_mismatch':bool(extra&0x4000),
            'mosi_level_mismatch':bool(extra&0x2000),'miso_low_during_response_wait':bool(extra&0x1000),
            'observed_pad_clock_rising_edges':extra&0xfff,'edge_count_saturated':(extra&0xfff)==0xfff,
            'scope':'FPGA端数字回读；不能证明卡槽接触、电源电压或全部电气条件正常'}
    return result
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('code',nargs='?');parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        old=decode('D000000007F80142');assert old['command']==0 and old['response']=='FF' and 'pad_trace' not in old
        normal=decode('SD D0000824C7F80142')['pad_trace'];assert normal['manual_round_generation']==1 and normal['observed_pad_clock_rising_edges']==1176 and not normal['clock_level_mismatch']
        newer=decode('D0001024C7F80142')['pad_trace'];assert newer['manual_round_generation']==2
        bad=decode('D0001C0007F80142')['pad_trace'];assert bad['clock_level_mismatch'] and bad['observed_pad_clock_rising_edges']==0
        print('PASS diagnostic decoder: legacy frame, new per-round trace, unchanged failure fields and forced pad fault')
    else:
        if args.code is None:parser.error('请提供诊断码，或使用 --self-test')
        print(json.dumps(decode(args.code),ensure_ascii=False,indent=2))
