#!/usr/local/bin/perl

use Device::SerialPort qw( :PARAM :STAT 0.07 );

my $SERIAL  = "/dev/cuaU0";
my $OUTFILE = "/usr/local/var/log/chktemp2.log";
local @SwapDevice = ( 0, 1, 2, 3, 4 );

my $STALL_DEFAULT = 10;
my $timeout       = $STALL_DEFAULT;
my $BreakPulse    = 4;
my $Sleep2Micro   = 0.002;
my $Sleep100Mil   = 0.1;
my $Sleep500Mil   = 0.5;
my $Sleep760Mil   = 0.76;
my $ID_RETRY      = 3;

# DS2480B
my $SIF_DATA        = 0xe1;
my $SIF_COMMAND     = 0xe3;
my $SIF_ACCON       = 0xb1;
my $SIF_ACCOFF      = 0xa1;
my $SIF_RST1W       = 0xc1;
my $SEARCHDATA_SIZE = 16;

# DS18B20
my $CMD_CONV   = 0x44;
my $CMD_RDPAD  = 0xbe;
my $CMD_WRPAD  = 0x4e;
my $SCPAD_SIZE = 9;

# common devices
my $ROM_SEARCH = 0xf0;
my $ROM_MATCH  = 0x55;
my $ROM_SKIP   = 0xcc;
my $ROMID_SIZE = 8;

# crc table
@dscrc_table = (
    0,   94,  188, 226, 97,  63,  221, 131, 194, 156, 126, 32,  163, 253,
    31,  65,  157, 195, 33,  127, 252, 162, 64,  30,  95,  1,   227, 189,
    62,  96,  130, 220, 35,  125, 159, 193, 66,  28,  254, 160, 225, 191,
    93,  3,   128, 222, 60,  98,  190, 224, 2,   92,  223, 129, 99,  61,
    124, 34,  192, 158, 29,  67,  161, 255, 70,  24,  250, 164, 39,  121,
    155, 197, 132, 218, 56,  102, 229, 187, 89,  7,   219, 133, 103, 57,
    186, 228, 6,   88,  25,  71,  165, 251, 120, 38,  196, 154, 101, 59,
    217, 135, 4,   90,  184, 230, 167, 249, 27,  69,  198, 152, 122, 36,
    248, 166, 68,  26,  153, 199, 37,  123, 58,  100, 134, 216, 91,  5,
    231, 185, 140, 210, 48,  110, 237, 179, 81,  15,  78,  16,  242, 172,
    47,  113, 147, 205, 17,  79,  173, 243, 112, 46,  204, 146, 211, 141,
    111, 49,  178, 236, 14,  80,  175, 241, 19,  77,  206, 144, 114, 44,
    109, 51,  209, 143, 12,  82,  176, 238, 50,  108, 142, 208, 83,  13,
    239, 177, 240, 174, 76,  18,  145, 207, 45,  115, 202, 148, 118, 40,
    171, 245, 23,  73,  8,   86,  180, 234, 105, 55,  213, 139, 87,  9,
    235, 181, 54,  104, 138, 212, 149, 203, 41,  119, 244, 170, 72,  22,
    233, 183, 85,  11,  136, 214, 52,  106, 43,  117, 151, 201, 74,  20,
    246, 168, 116, 42,  200, 150, 21,  75,  169, 247, 182, 232, 10,  84,
    215, 137, 107, 53
);

# init Serial port
sub init_serial {
    my $port = Device::SerialPort->new($SERIAL)
      || die "Can't open $SERIAL: $!\n";

    $port->read_char_time(10);
    $port->read_const_time(100);
    $port->baudrate(9600);
    $port->databits(8);
    $port->parity("none");
    $port->handshake("none");
    return $port;
}

sub reset2840b {
    my $port = $_[0];

    $port->pulse_break_on($BreakPulse);             # Reset 2480B
    select( undef, undef, undef, $Sleep2Micro );    # Wait for 2480B
}

sub reset1wire {
    my $port = $_[0];
    my $out, $count;
    my @ret;

    $out   = pack "c", 0xc1;
    $count = $port->write($out);                    # reset w1-bus
    if ( $count == 0 ) {
        print "Can't RESET";
        exit 1;
    }
    select( undef, undef, undef, $Sleep100Mil );    # Wait for 2480B
    ( $count, $out ) = $port->read(1);
    @ret = unpack "c", $out;

    #    printf("reset result: %02x :%d\n", $ret[0] & 0xff, $count);
    return $ret[0] & 0xff;
}

sub reset1wire_flush {
    my $port = $_[0];
    my $out, $count;
    my @ret;

    $out   = pack "c", 0xc1;
    $count = $port->write($out);    # reset w1-bus
    if ( $count == 0 ) {
        print "Can't RESET";
        exit 1;
    }
    select( undef, undef, undef, $Sleep100Mil );    # Wait for 2480B
    ( $count, $out ) = $port->read(8);
    @ret = unpack "c", $out;

    #    printf("reset result: %02x :%d\n", $ret[0] & 0xff, $count);
    return $ret[0] & 0xff;
}

sub write1 {
    my $port  = $_[0];
    my $wdata = $_[1];
    my $out, $count, $ret;

    $out   = pack "c", $wdata;
    $count = $port->write($out);
    if ( $count < 1 ) {
        printf( "Fail write DS2380B %d\n", $count );
        exit 1;
    }
    return 1;
}

sub data_writeread1 {
    my $port  = $_[0];
    my $wdata = $_[1];

    if ( $wdata == $SIF_COMMAND ) {
        writeread1( $port, $wdata );
    }
    $ret = writeread1( $port, $wdata );
    return $ret;
}

sub data_write1 {
    my $port  = $_[0];
    my $wdata = $_[1];

    if ( $wdata == $SIF_COMMAND ) {
        write1( $port, $wdata );
    }
    $ret = write1( $port, $wdata );
    return $ret;
}

sub writeread1 {
    my $port  = $_[0];
    my $wdata = $_[1];
    my $out, $count;
    my @ret;

    $out   = pack "c", $wdata;
    $count = $port->write($out);
    if ( $count < 1 ) {
        printf( "Fail write DS2380B %d\n", $count );
        exit 1;
    }
    else {
        select( undef, undef, undef, $Sleep2Micro );    # Wait for 2480B
        $count = 0;
        while ( $count == 0 ) {
            ( $count, $out ) = $port->read(1);
            @ret = unpack "c", $out;

            # 	    printf("Read result %d bytes, data %02x\n", $count, $ret[0]);
        }
    }
    return $ret[0];
}

# DS18B20

sub convert_all {
    my $port;
    my $presence, $i, $count;

    $port = $_[0];

    write1( $port, $SIF_COMMAND );    # set command mode
    $presence = reset1wire($port);
    write1( $port, $SIF_DATA );       # set data mode
    data_writeread1( $port, $ROM_SKIP );
    data_writeread1( $port, $CMD_CONV );
    write1( $port, $SIF_COMMAND );    # set command mode
    select( undef, undef, undef, $Sleep760Mil );
    $presence = reset1wire($port);
    return 1;
}

# read scratchpad
sub read_scratchpad {
    my $port;
    my @id;                           # 8byte(64bits ID)
    my $presence, $i,   $count;
    my @scpad,    $out, @tmp;

    ( $port, @id ) = @_;
    write1( $port, $SIF_COMMAND );    # set command mode
    $presence = reset1wire($port);
    write1( $port, $SIF_DATA );       # set data mode
    data_writeread1( $port, $ROM_MATCH );
    for ( $i = 0 ; $i < $ROMID_SIZE ; $i++ ) {
        data_writeread1( $port, $id[$i] );
    }

    #    printf("\n");
    #    $port->read(8);
    data_writeread1( $port, $CMD_RDPAD );
    select( undef, undef, undef, $Sleep2Micro );    # Wait for 2480B
    for ( $i = 0 ; $i < 9 ; $i++ ) {
        $out = writeread1( $port, 0xff );
        $scpad[$i] = $out & 0xff;
    }
    write1( $port, $SIF_COMMAND );                  # set command mode
    $presence = reset1wire($port);
    return @scpad;
}

# DS2840B detect & configuration
sub detect {
    my $port = $_[0];
    my $done = 0;
    my $count, $out;

    reset1wire($port);
    $out = writeread1( $port, 0x17 );

    #    printf("data %02x\n", $out & 0xff);
    $out = writeread1( $port, 0x45 );

    #    printf("data %02x\n", $out & 0xff);
    $out = writeread1( $port, 0x51 );

    #    printf("data %02x\n", $out & 0xff);
    $out = writeread1( $port, 0x0f );

    #    printf("data %02x\n", $out & 0xff);
    $out = writeread1( $port, 0x91 );

    #    printf("data %02x\n", $out & 0xff);
}

sub id_nibble {
    my $inbyte = $_[0];
    my $out, $i;

    $out = 0;
    for ( $i = 0 ; $i < 4 ; $i++ ) {
        $out <<= 1;
        $out |= 1 if ( $inbyte & 0x80 );
        $inbyte <<= 2;
    }
    return $out;
}

sub id_pick {
    my @data = @_;
    my $i, $j;
    my @id;

    for ( $i = 0 ; $i < 16 ; $i += 2 ) {
        $id[ $i / 2 ] =
          id_nibble( $data[$i] ) + ( id_nibble( $data[ $i + 1 ] ) << 4 );
    }
    return @id;
}

sub lastb_bit {

    # 検索アクセラレータの出力データから次の検索アクセラレータの入力データを
    # 作るための下位ルーチン bit単位の処理を担当

    # 入力: 検索アクセラレータの出力データの1byte分 ((rm , dm)の4個のペア)
    # 出力: out - LASTBの位置に対応するrm=1, ri=0 (i:i>m)とした1byteのデータ
    #     : lastb_pos - 1byte内でのLASTBの位置
    # {i: i<m} の範囲についてはriは入力のコピー
    my $accdata    = $_[0] & 0xff;
    my $lastb_flag = 0;
    my $dflag_mask = 0x40;
    my $index_mask = 0x80;
    my $lastb_pos  = 0;
    my $i, $out;

    $out = 0;
    for ( $i = 0 ; $i < 4 ; $i++ ) {
        if ( $lastb_flag == 0 ) {
            if ( ( $accdata & $dflag_mask ) && ( $accdata & $index_mask ) == 0 )
            {
                $lastb_flag = 1;
                $out |= $index_mask;
                $lastb_pos = 4 - $i;
            }
        }
        else {
            $out |= $accdata & $index_mask;
        }
        $dflag_mask >>= 2;
        $index_mask >>= 2;
    }
    return ( $out, $lastb_pos );
}

sub next_search_data {
    my @search_data;
    my $i,      $flag = 0;
    my @out,    $pos_byte;
    my $lastbb, $lastb_pos, $lastb_search;
    my $r,      $d;

    # 検索アクセラレータの出力データから次の検索アクセラレータ入力データを作る
    # 戻り値の最初のデータ(不一致点)が負の場合は検索終了を意味する

    # 入力: 検索アクセラレータの出力
    # 出力: $lastb_search - LASTB 次に検索を開始する不一致点(0～63)
    #     : @out  - 次の検索アクセラレータ入力データ
    @search_data = @_;

    # 不一致ビットが1で対応する$rが0のノードを探す
    # $rが1のノードは両方の枝が検索済み
    # バイト単位で最大の不一致点を探す
    for ( $lastbb = 0, $i = 0 ; $i < $SEARCHDATA_SIZE ; $i++ ) {
        if ( ( $d = ( $search_data[$i] & 0x55 ) ) > 0 ) {
            $r = ( $search_data[$i] & 0xaa ) >> 1;
            if ( ( $d & ( ~$r ) ) > 0 ) {
                $lastbb = $i;
            }
        }
    }
    if ( $lastbb == 0 && $i == $SEARCHDATA_SIZE ) {

        # 未検索の不一致点が存在しない - 検索終了
        return -1, @out;
    }
    else {
        for ( $i = 0 ; $i < $lastbb ; $i++ ) {
            $out[$i] = $search_data[$i];
        }
        ( $out[$lastbb], $lastb_pos ) = lastb_bit( $search_data[$lastbb] );
        for ( $i = $lastbb + 1 ; $i < $SEARCHDATA_SIZE ; $i++ ) {
            $out[$i] = 0;
        }
        $lastb_search = $lastbb * 4 + $lastb_pos;
        return $lastb_search, @out;
    }
}

sub dump_search_data {
    my @search_data = @_;

    printf("direct data:\n");
    for ( $i = 0 ; $i < 16 ; $i++ ) {
        printf( " %02x", $search_data[$i] & 0xaa );
    }
    printf("\numatch data:\n");
    for ( $i = 0 ; $i < 16 ; $i++ ) {
        printf( " %02x", $search_data[$i] & 0x55 );
    }
    printf("\n");
}

sub search_acc {
    my $port;
    my @search_data;
    my $count, $countr, $out, $i;
    my @ret, @acc_out;

    ( $port, @search_data ) = @_;
    reset1wire($port);
    select( undef, undef, undef, $Sleep2Micro );    # Wait for 2480B
    write1( $port, $SIF_DATA );                     # data mode
    write1( $port, $ROM_SEARCH );                   # Search ROM cmd
    write1( $port, $SIF_COMMAND );                  # command mode
    write1( $port, $SIF_ACCON );                    # Search Accelerarator On
    write1( $port, $SIF_DATA );                     # data mode

    for ( $i = 0 ; $i < 16 ; $i++ ) {               # search init data
        $out = data_write1( $port, $search_data[$i] );
    }
    write1( $port, $SIF_COMMAND );                  # command mode
    write1( $port, $SIF_ACCOFF );                   # Search Accelerarator Off
    write1( $port, $SIF_DATA );                     # data mode
    for ( $i = 0 ; $i < 17 ; $i++ ) {
        ( $countr, $out ) = $port->read(1);
        @ret = unpack "c", $out;
        if ( $i > 0 ) {
            $acc_out[ $i - 1 ] = $ret[0] & 0xff;
        }
    }
    $out = write1( $port, $SIF_COMMAND );           # command mode
    reset1wire($port);
    return @acc_out;
}

sub search_ids {
    my $port = $_[0];
    my $count, $countr, $i, $j;
    my @id, @acc_out;
    my $devices = 0;
    my @ids;
    my @outbound_acc;
    my $lastb = 999;

    for ( $i = 0 ; $i < 16 ; $i++ ) {
        $outbound_acc[$i] = 0x00;
    }

    while ( $lastb > 0 ) {
        @outbound_acc = search_acc( $port, @outbound_acc );
        @id           = id_pick(@outbound_acc);
        for ( $i = 0 ; $i < 8 ; $i++ ) {
            $ids[$devices]->[$i] = $id[$i];
        }
        $lastb_prev = $lastb;
        ( $lastb, @outbound_acc ) = next_search_data(@outbound_acc);
        $devices++;
    }
    return ( $devices, @ids );
}

sub dscrc8 {
    my $utilcrc8 = 0;
    my $i;

    ( $size, @data ) = @_;
    for ( $i = 0 ; $i < $size ; $i++ ) {
        $utilcrc8 = $dscrc_table[ $utilcrc8 ^ ( $data[$i] & 0xff ) ];
    }
    return $utilcrc8;
}

sub chk_romid {
    my @idmat;
    my $devices, $crc;
    my $i, $j, @temp;

    ( $devices, @idmat ) = @_;
    for ( $i = 0 ; $i < $devices ; $i++ ) {
        for ( $j = 0 ; $j < $ROMID_SIZE ; $j++ ) {
            $temp[$j] = $idmat[$i][$j];
        }
        $crc = dscrc8( 7, @temp );
        if ( $crc != $idmat[$i][ $j - 1 ] ) {
            return 0;
        }
    }
    return $crc;
}

sub chk_scpad {
    my @scpad = @_;
    my $devices;
    my $i;

    #    for($i = 0; $i < $SCPAD_SIZE; $i++) {
    #	    printf(" %02x",$scpad[$i]);
    #    }
    #    printf("\n");
    $crc = dscrc8( 8, @scpad );

    #    printf("CRC:%02x, %02x\n", $crc, $scpad[$SCPAD_SIZE-1]);
    if ( $crc != $scpad[ $SCPAD_SIZE - 1 ] ) {
        return 0;
    }
    return 1;
}

sub read_temper {
    my @scpad = @_;
    my $devices;
    my $i;

    if ( !chk_scpad(@scpad) ) {
        return -255;
    }
    else {
        return ( $scpad[0] + $scpad[1] * 256 ) / 16;
    }
}

my $port = init_serial();
my @scpad, @idr, $dev, $d;
my $i;

open OUTF, ">>$OUTFILE" or die "Can't open logfile";
print OUTF "serial_init done\n";

reset2840b($port);
print OUTF "reset 2840B done\n";
detect($port);

print OUTF "configure 2840B\n";

for ( $i = 0 ; $i < $ID_RETRY ; $i++ ) {
    ( $devices, @ids ) = search_ids($port);
    if ( chk_romid( $devices, @ids ) > 0 ) {
        last;
    }
}
die "ROMID CRC error" if ( $i == $ID_RETRY );

for ( $i = 0 ; $i < $devices ; $i++ ) {
    $dev = $SwapDevice[$i];
    printf OUTF "Device %d ID: ", $dev;
    for ( $j = 0 ; $j < $ROMID_SIZE ; $j++ ) {
        printf OUTF "%02x", $ids[$dev][$j];
        if ( $j == 0 || $j == 6 ) {
            printf OUTF "-";
        }
    }
    printf OUTF "\n";
}

close OUTF;

while (1) {
    convert_all($port);
    write1( $port, $SIF_COMMAND );    # command mode
    reset1wire_flush($port);

    open OUTF, ">>$OUTFILE" or die "Can't open logfile";
    print OUTF scalar localtime;
    for ( $d = 0 ; $d < $devices ; $d++ ) {
        $dev = $SwapDevice[$d];
        for ( $i = 0 ; $i < 8 ; $i++ ) {
            $idr[$i] = $ids[$dev]->[$i];
        }
        @scpad = read_scratchpad( $port, @idr );
        printf OUTF ",%5.1f", read_temper(@scpad);
    }
    printf OUTF "\n";
    close OUTF;
    sleep 2;
}
