function [ofdm_data, framed_data, mapped_data, syminterleaved_data, ...
          bitinterleaved_data, punctured_data, convencoded_data, ...
          convinterleaved_data, rsencoded_data, scrambled_data] ...
          = dvbt_signal_generation(datain, mode, cp_ratio, M, fec, outpower)
% The function DVBT_SIGNAL_GENERATION produces the OFDM symbols
% that constitute the signal generated by a DVB-T transmitter. 
% The function is called as
%
% [ofdm_data, framed_data, mapped_data, syminterleaved_data, ...
%  bitinterleaved_data, punctured_data, convencoded_data,...
%  convinterleaved_data, rsencoded_data, scrambled_data] ...
%  = dvbt_signal_generation(datain, mode, cp_ratio, M, fec, outpower)
%
% where the input parameters
% datain   is the generated data (a matrix of bytes with 188 rows),
% mode     is the DVB-T mode (equal to '2k', '4k', or '8k'),
% cp_ratio is the cyclic prefix ratio (equal to '1/32', '1/16', '1/8', or '1/4'),
% M        is the QAM size (equal to 4, 16, or 64),
% fec      is the FEC ratio (equal to '1/2', '2/3', '3/4', '5/6', or '7/8'),
% outpower is the percentage of output power (can be larger than 100),
%
% while the output parameters
% ofdm_data            are the complex-valued baseband samples,
% framed_data          are the frequency-domain active carrier data cells,
% mapped_data          are the QAM data symbols,
% syminterleaved_data  are the symbol interleaved data symbols,
% bitinterleaved_data  are the bit interleaved data symbols,
% punctured_data       are the punctured data bits,
% convencoded_data     are the convolutionally encoded data bits,
% convinterleaved_data are the convolutionally interleaved data bits,
% rsencoded_data       are the Reed-Solomon encoded data bytes,
% scrambled_data       are the scrambled data bytes.

% (c) 2016 The DVB-TX-IRIS team, University of Perugia
 
% number of total carriers, data carriers, active carriers, pilot carriers, TPS carriers, and interleaving parameters
if strcmp(mode,'2k'),
    Mmax = 2048; Nmax = 1512; Kmax = 1705; Pmax =  45; Tmax = 17; R1mask = [1 0 0 1 0 0 0 0 0 0]; r1perm = [4 3 9 6 2 8 1 5 7 0];
elseif strcmp(mode,'4k'),
    Mmax = 4096; Nmax = 3024; Kmax = 3409; Pmax =  89; Tmax = 34; R1mask = [1 0 1 0 0 0 0 0 0 0 0]; r1perm = [6 3 0 9 4 2 1 8 5 10 7];
elseif strcmp(mode,'8k'),
    Mmax = 8192; Nmax = 6048; Kmax = 6817; Pmax = 177; Tmax = 68; R1mask = [1 1 0 0 1 0 1 0 0 0 0 0]; r1perm = [7 1 4 2 9 6 8 10 0 3 11 5];
else
    error('Invalid DVB-T mode.')
end

% cyclic prefix of OFDM
if strcmp(cp_ratio,'1/32'),
    Dmax = 32;
elseif strcmp(cp_ratio,'1/16'),
    Dmax = 16;
elseif strcmp(cp_ratio,'1/8'),
    Dmax = 8;
elseif strcmp(cp_ratio,'1/4'),
    Dmax = 4;
else
    error('Invalid cyclic prefix.')
end

% QAM constellation
if M == 4,
    QAM = [+1+1i; +1-1i; -1+1i; -1-1i]/sqrt(2); dmx = [1 2];
elseif M == 16,
    QAM = [+3+3i; +3+1i; +1+3i; +1+1i; +3-3i; +3-1i; +1-3i; +1-1i; -3+3i; -3+1i; -1+3i; -1+1i; -3-3i; -3-1i; -1-3i; -1-1i]/sqrt(10); dmx = [1 3 2 4];
elseif M == 64,
    QAM = [+7+7i; +7+5i; +5+7i; +5+5i; +7+1i; +7+3i; +5+1i; +5+3i; +1+7i; +1+5i; +3+7i; +3+5i; +1+1i; +1+3i; +3+1i; +3+3i;...
        +7-7i; +7-5i; +5-7i; +5-5i; +7-1i; +7-3i; +5-1i; +5-3i; +1-7i; +1-5i; +3-7i; +3-5i; +1-1i; +1-3i; +3-1i; +3-3i;...
        -7+7i; -7+5i; -5+7i; -5+5i; -7+1i; -7+3i; -5+1i; -5+3i; -1+7i; -1+5i; -3+7i; -3+5i; -1+1i; -1+3i; -3+1i; -3+3i;...
        -7-7i; -7-5i; -5-7i; -5-5i; -7-1i; -7-3i; -5-1i; -5-3i; -1-7i; -1-5i; -3-7i; -3-5i; -1-1i; -1-3i; -3-1i; -3-3i]/sqrt(42); dmx = [1 4 2 5 3 6];
else
    error('Invalid QAM size.')
end

% puncturing table
if strcmp(fec,'1/2'),
    pu_table = [1 1]';
elseif strcmp(fec,'2/3'),
    pu_table = [1 1; 0 1]';
elseif strcmp(fec,'3/4'),
    pu_table = [1 1; 0 1; 1 0]';
elseif strcmp(fec,'5/6'),
    pu_table = [1 1; 0 1; 1 0; 0 1; 1 0]';
elseif strcmp(fec,'7/8'),
    pu_table = [1 1; 0 1; 0 1; 0 1; 1 0; 0 1; 1 0]';
else
    error('Invalid FEC type.')
end

% check the size of the input data
[nrows,npack8] = size(datain);
if nrows ~= 188,
    error('The number of rows of datain must be equal to 188.')
end
if mod(npack8,8)~=0,
    error('The number of columns of datain must be a multiple of 8.')
end

% ----------
% SCRAMBLING
% ----------
K = 188; % number of bytes in each packet
grouplen = K*8*8; 
ngroups  = npack8/8;
datain(1,1:8:end) = repmat(184,1,length(datain(1,1:8:end))); % inverted SYNC is 184
bin  = reshape(de2bi(datain(:),8,'left-msb').', grouplen, ngroups);
bout = zeros(size(bin));
bout(1:8,:) = bin(1:8,:); % pass inverted SYNC byte
register = [1 0 0 1 0 1 0 1 0 0 0 0 0 0 0]; % register load
for ii = 8:(grouplen-1),
    tmpxor = xor(register(14),register(15)); % register output
    register = [tmpxor,register(1:14)]; % shift register
    if mod(ii,K*8) < 8,
        tmpxor = 0; % pass SYNC byte
    end;
    bout(ii+1,:) = xor(tmpxor*ones(1,ngroups),bin(ii+1,:)); % xor
end;
scrambled_data = reshape(bout, 8, []).';
scrambled_data = bi2de(scrambled_data,'left-msb');
scrambled_data = reshape(scrambled_data,K,npack8); % K x npack8 bytes

% -----------
% RS ENCODING
% -----------
Kfull = 239; % number of bytes at the input of the RS encoder, including 51 zeros
Nfull = 255; % number of bytes at the output of the RS encoder, including 51 zeros
% N   = 204; % number of bytes at the output of the shortened RS encoder
rs_genpoly     = rsgenpoly(Nfull,Kfull,285,0); % primitive polynomial is 285
msg            = gf([zeros(Kfull-K,npack8);scrambled_data].', 8);
cw             = rsenc(msg,Nfull,Kfull,rs_genpoly);
cw8            = uint8(cw.x);
rsencoded_data = double(cw8(:,(Kfull-K+1):end).'); % N x npack8 bytes

% --------------------------
% CONVOLUTIONAL INTERLEAVING
% --------------------------
I_ci = 12; % number of delay paths of the interleaver
M_ci = 17; % number of bytes in each memory cell of each delay path
mem_conv = randi([0 255],sum(1:(I_ci-1)),M_ci); % The memory of the convolutional interleaver is initialized with random values
tdata = reshape(rsencoded_data,I_ci,[]);
numI  = size(tdata,2);
idata = zeros(size(tdata));
for ii = 0:(I_ci-1),
    idata(ii+1,(0:(numI-1))+ii*M_ci+1) = tdata(ii+1,:); % useful data
    idata((ii+2):I_ci,(ii*M_ci+1):((ii+1)*M_ci)) = mem_conv((-0.5*((ii+1).^2)+12.5*(ii+1)-11):(-0.5*((ii+1).^2)+11.5*(ii+1)),1:M_ci); % random data
end;
convinterleaved_data = idata(:, 1:numI);
convinterleaved_data = reshape(convinterleaved_data,I_ci*numI,1); % N*npack8 x 1 bytes

% ----------------------
% CONVOLUTIONAL ENCODING
% ----------------------
clen       = 7; % constraint length of the convolutional encoder
ce_genpoly = [171 133]; % generator polynomial of the convolutional encoder
trellis = poly2trellis(clen, ce_genpoly); % convolutional code trellis
uncoded = de2bi(convinterleaved_data,8,'left-msb').';
convencoded_data = convenc(uncoded(:), trellis); % 2*N*npack8*8 x 1 bits

% ----------
% PUNCTURING
% ----------
pw = size(pu_table, 2); % puncturing period
datalen = length(convencoded_data);  % length of puncturing input
datalen = datalen - mod(datalen,2*pw); % matches the length of the puncturing input to the puncturing period
data = convencoded_data(1:datalen,1);
tdata = reshape(data, 2, []); % data in puncturing format
pm = logical(repmat(pu_table, 1, datalen / (2*pw) )); % selection matrix
punctured_data = tdata(pm); % floor(N*npack8*8/fec) x 1 bits

% ----------------
% BIT INTERLEAVING
% ----------------
Isize = 126; % number of bits for each RAM of the bit interleaver 
woff  = [0 63 105 42 21 84]; % column offsets of the six RAMs
binlen = length(punctured_data);
binlen = binlen - mod(binlen,12*Isize);
xr = reshape(punctured_data(1:binlen,1), log2(M), []); % reshape for demultiplexing
b = xr(dmx, :); % demultiplex
w = 0:(size(b, 2) - 1); % column index
a = zeros(size(b));
for e = 1:log2(M),
    wi = Isize .* floor(w / Isize) + mod(w + woff(e), Isize); % interleaved column index
    a(e,:) = b(e,wi+1); % interleave bits
end;
bitinterleaved_data = bi2de(a', 'left-msb'); % (12*Isize/log2(M))*floor(floor(N*npack8*8/fec)/(12*Isize)) x 1 symbols

% -------------------
% SYMBOL INTERLEAVING
% -------------------
symlen = length(bitinterleaved_data);
symlen = symlen - mod(symlen,Nmax);
x = bitinterleaved_data(1:symlen,1);
Nr = log2(Mmax);
R1 = zeros(Mmax, Nr - 1);
R1(1, :) = zeros(1, Nr - 1);
R1(2, :) = zeros(1, Nr - 1);
R1(3, :) = [1 zeros(1, Nr - 2)];
for ii = 4:Mmax,
    R1(ii, 1:(Nr - 2)) = R1(ii - 1, 2:(Nr - 1));
    R1(ii, Nr - 1) = mod(sum(R1(ii - 1, :) .* R1mask), 2);
end;
R = zeros(size(R1));
R(:, r1perm + 1) = R1;
Hall = bi2de(R) + pow2(Nr - 1) .* mod(0:(Mmax - 1), 2)';
Hlist = Hall(Hall < Nmax);
data = reshape(x, Nmax, []); % form OFDM symbols
idata = zeros(size(data));
idata(Hlist + 1, 1:2:size(data, 2)) = data(:, 1:2:size(data, 2)); % apply interleaving on even symbols: q -> H(q)
idata(:, 2:2:size(data, 2)) = data(Hlist + 1, 2:2:size(data, 2)); % apply interleaving on odd symbols: H(q) -> q
syminterleaved_data = idata;  % Nmax x floor(((12*Isize/log2(M))*floor(floor(N*npack8*8/fec)/(12*Isize)))/Nmax) symbols

% -------
% MAPPING
% -------
mapped_data = QAM(syminterleaved_data + 1); % Nmax x floor(((12*Isize/log2(M))*floor(floor(N*npack8*8/fec)/(12*Isize)))/Nmax) symbols

% -------
% FRAMING
% -------
cont_pil_list = [   0   48   54   87  141  156  192  201  255  279  282  333  432  450  483 ...
    525  531  618  636  714  759  765  780  804  873  888  918  939  942  969  984 ...
    1050 1101 1107 1110 1137 1140 1146 1206 1269 1323 1377 1491 ...
    1683 1704 1752 1758 1791 1845 1860 1896 1905 1959 1983 1986 ...
    2037 2136 2154 2187 2229 2235 2322 2340 2418 2463 2469 2484 ...
    2508 2577 2592 2622 2643 2646 2673 2688 2754 2805 2811 2814 2841 2844 2850 2910 2973 ...
    3027 3081 3195 3387 3408 3456 3462 3495 ...
    3549 3564 3600 3609 3663 3687 3690 3741 3840 3858 3891 3933 3939 ...
    4026 4044 4122 4167 4173 4188 4212 4281 4296 4326 4347 4350 4377 4392 4458 ...
    4509 4515 4518 4545 4548 4554 4614 4677 4731 4785 4899 ...
    5091 5112 5160 5166 5199 5253 5268 5304 5313 5367 5391 5394 5445 ...
    5544 5562 5595 5637 5643 5730 5748 5826 5871 5877 5892 5916 5985 ...
    6000 6030 6051 6054 6081 6096 6162 6213 6219 6222 6249 6252 6258 6318 6381 6435 6489 ...
    6603 6795 6816]; % location of continual pilots
tps_pil_list  = [  34   50  209  346  413  569  595  688  790  901 ...
    1073 1219 1262 1286 1469 1594 1687 1738 1754 1913 ...
    2050 2117 2273 2299 2392 2494 2605 2777 2923 2966 2990 ...
    3173 3298 3391 3442 3458 3617 3754 3821 3977 ...
    4003 4096 4198 4309 4481 4627 4670 4694 4877 ...
    5002 5095 5146 5162 5321 5458 5525 5681 5707 5800 5902 ...
    6013 6185 6331 6374 6398 6581 6706 6799]; % location of TPS carriers
cont_pil_list = cont_pil_list(1:Pmax); % set pilot locations
tps_pil_list  =  tps_pil_list(1:Tmax); % set TPS locations
reg = zeros(Kmax, 11); % reference PRBS
reg(1, :) = 1;
for ss = 2:size(reg, 1),
    reg(ss, 2:11) = reg(ss - 1, 1:10);
    reg(ss, 1) = mod(reg(ss - 1, 9) + reg(ss - 1, 11), 2);
end;
w_prbs = reg(:, 11);
pil_amplitude = 4/3; pil_distance = 12; pil_mod = 3; % pilot parameters
tps_amplitude = 1; % TPS amplitude
ns = size(mapped_data.', 1); % ns = floor(((12*Isize/log2(M))*floor(floor(N*npack8*8/fec)/(12*Isize)))/Nmax); % number of OFDM symbols
maps = zeros(ns, Kmax); % memory allocation
tps = zeros(68, 1); % memory allocation
tps(0+1) = 0; % don't care
tps(( 1:16)+1) = [0 0 1 1 0 1 0 1 1 1 1 0 1 1 1 0];    % synchro word 1-3   % = [1 1 0 0 1 0 1 0 0 0 0 1 0 0 0 1]; % synchro word 2-4
tps((17:22)+1) = [0 1 0 1 1 1]; % length indicator
tps((23:24)+1) = [0 0]; % frame counter
tps((25:26)+1) = [M==64  M==16]; % QAM
tps((27:29)+1) = [0 0 0]; % NH             % = [0 0 1]; % alpha=1  % = [0 1 0]; % alpha=2  % = [0 1 1]; % alpha=4
tps((30:32)+1) = strcmp(fec,'1/2')*[0 0 0] + strcmp(fec,'2/3')*[0 0 1] + strcmp(fec,'3/4')*[0 1 0] + strcmp(fec,'5/6')*[0 1 1] + strcmp(fec,'7/8')*[1 0 0];
tps((33:35)+1) = [0 0 0]; % LP 1/2 or NH   % = [0 0 1]; % LP 2/3   % = [0 1 0]; % LP 3/4   % = [0 1 1]; % LP 5/6   % = [1 0 0]; % LP 7/8
tps((36:37)+1) = [(Dmax==4)+(Dmax==8)  (Dmax==4)+(Dmax==16)]; % [0 0] for 1/32,  [0 1] for 1/16,  [1 0] for 1/8,  [1 1] for 1/4
tps((38:39)+1) = [Mmax==4096  Mmax==8192];  % DVB mode
tps((40:47)+1) = [0 0 0 0 0 0 0 0]; % cellid, set to zero
tps((48:53)+1) = [0 0 0 0 0 0]; % see Annex F
sc = 0; % symbol counter
fc = 0; % frame counter
for l = 0:(ns - 1),
    pilpos = (0:pil_distance:(Kmax-1)) + mod(sc*pil_mod, pil_distance); % location of the scattered pilots
    if pilpos(end) > Kmax - 1,
        pilpos(end) = [];
    end;
    maps(l + 1, pilpos + 1) = pil_amplitude .* 2 .* (0.5 - w_prbs(pilpos + 1)'); % place the scattered pilots
    maps(l + 1, cont_pil_list + 1) = pil_amplitude .* 2 .* (0.5 - w_prbs(cont_pil_list + 1)'); % place the continual pilots
    if sc == 0,
        if fc == 0 || fc == 2,
            tps((1:16)+1) = [0 0 1 1 0 1 0 1 1 1 1 0 1 1 1 0]; % synchro word 1-3
        else
            tps((1:16)+1) = [1 1 0 0 1 0 1 0 0 0 0 1 0 0 0 1]; % synchro word 2-4
        end;
        tps((23:24)+1) = de2bi(fc,2,'left-msb'); % frame counter
        msg = [zeros(1, 60) tps(2:54).'];
        cwext = bchenc(gf(msg), 127, 113); cw = cwext.x; % for compatibility with OCTAVE, replace this line with the following line
        % cw = fliplr(bchenco(fliplr(msg), 127, 113, [1 0 0 0 0 1 1 0 1 1 1 0 1 1 1]));
        tps((54:67) + 1) = cw(114:127); % parity
        maps(l + 1, tps_pil_list + 1) = tps_amplitude .* 2 .* (0.5 - w_prbs(tps_pil_list + 1).'); % absolute modulation
    else
        maps(l + 1, tps_pil_list + 1) = (2*(tps(sc+1)==0) - 1) .* maps((l - 1) + 1, tps_pil_list + 1);   % differential modulation
    end;
    maps(l + 1, maps(l + 1, :) == 0) = (mapped_data(: , l + 1)).'; % fill remaining cells with data
    sc = mod(sc + 1, 68); % update symbol counter
    fc = mod(fc + 1,  4); % update  frame counter
end;
framed_data = maps; % ns x Kmax frequency-domain symbols

% ----
% OFDM
% ----
f = 3; % map -3sigma...+3sigma into -1...+1
multFactor_ = Mmax * sqrt(outpower/(50 * f^2 * (1 * (Nmax + Tmax) + (16/9) * (Kmax - Nmax - Tmax))));
ofdms = zeros(ns, Mmax + Mmax/Dmax); % memory allocation
for l = 1:ns,
    fdata = [framed_data(l, :) zeros(1, Mmax - Kmax)]; % add null (virtual) carriers as guard band
    fdata = circshift(fdata.', -(Kmax-1)/2).'; % carrier reordering
    tdata = ifft(fdata) * multFactor_ ; % IFFT
    ofdms(l, :) = [tdata((end - Mmax/Dmax + 1):end) tdata]; % add cyclic prefix
end;
ofdm_data = reshape(ofdms.', [], 1); % ns*(Mmax+Mmax/Dmax) x 1 time-domain samples

