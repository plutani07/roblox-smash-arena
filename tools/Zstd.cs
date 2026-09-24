// Minimal Zstandard decoder (RFC 8878), modeled on the reference "educational decoder".
// C# 5 compatible so it builds with the .NET Framework csc.exe.
using System;
using System.Collections.Generic;

public static class Zstd
{
    class FseTable
    {
        public int AccLog;
        public byte[] Symbols;
        public byte[] NumBits;
        public ushort[] Base;
    }

    class HufTable
    {
        public int MaxBits;
        public byte[] Symbols;
        public byte[] NumBits;
    }

    class Ctx
    {
        public ulong[] Rep = new ulong[] { 1, 4, 8 };
        public HufTable Huf;
        public FseTable LL, OF, ML;
    }

    static readonly short[] LL_DEF = {4,3,2,2,2,2,2,2,2,2,2,2,2,1,1,1,2,2,2,2,2,2,2,2,2,3,2,1,1,1,1,1,-1,-1,-1,-1};
    static readonly short[] OF_DEF = {1,1,1,1,1,1,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,-1,-1,-1,-1,-1};
    static readonly short[] ML_DEF = {1,4,3,2,2,2,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,-1,-1,-1,-1,-1,-1,-1};

    static readonly uint[] LL_BASE = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,20,22,24,28,32,40,48,64,128,256,512,1024,2048,4096,8192,16384,32768,65536};
    static readonly byte[] LL_BITS = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,2,2,3,3,4,6,7,8,9,10,11,12,13,14,15,16};
    static readonly uint[] ML_BASE = {3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,37,39,41,43,47,51,59,67,83,99,131,259,515,1027,2051,4099,8195,16387,32771,65539};
    static readonly byte[] ML_BITS = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,2,2,3,3,4,4,5,7,8,9,10,11,12,13,14,15,16};

    static int HighBit(ulong v)
    {
        int r = -1;
        while (v != 0) { v >>= 1; r++; }
        return r;
    }

    // ---- forward bit reader (FSE table headers) ----
    class Fwd
    {
        byte[] d; public int Pos; int bit;
        public Fwd(byte[] d, int pos) { this.d = d; Pos = pos; bit = 0; }
        public int Read(int n)
        {
            int v = 0;
            for (int i = 0; i < n; i++)
            {
                int b = (d[Pos] >> bit) & 1;
                v |= b << i;
                bit++;
                if (bit == 8) { bit = 0; Pos++; }
            }
            return v;
        }
        public void Rewind(int n)
        {
            for (int i = 0; i < n; i++)
            {
                if (bit == 0) { bit = 8; Pos--; }
                bit--;
            }
        }
        public void Align() { if (bit != 0) { bit = 0; Pos++; } }
    }

    // ---- backward bitstream helpers ----
    static ulong ReadBitsLE(byte[] src, int start, int numBits, long bitOff)
    {
        ulong res = 0;
        for (int i = 0; i < numBits; i++)
        {
            long bo = bitOff + i;
            int b = (src[start + (int)(bo >> 3)] >> (int)(bo & 7)) & 1;
            res |= (ulong)b << i;
        }
        return res;
    }

    static ulong StreamRead(byte[] src, int start, int bits, ref long offset)
    {
        offset -= bits;
        long actualOff = offset;
        int actualBits = bits;
        if (offset < 0) { actualBits += (int)offset; actualOff = 0; }
        ulong res = actualBits > 0 ? ReadBitsLE(src, start, actualBits, actualOff) : 0;
        if (offset < 0)
        {
            long sh = -offset;
            res = sh >= 64 ? 0 : (res << (int)sh);
        }
        return res;
    }

    static long StartOffset(byte[] src, int start, int len)
    {
        if (len <= 0) throw new Exception("zstd: empty bitstream");
        byte last = src[start + len - 1];
        if (last == 0) throw new Exception("zstd: bad bitstream padding");
        int padding = 8 - HighBit(last);
        return (long)len * 8 - padding;
    }

    // ---- FSE ----
    static FseTable FseBuild(short[] norm, int numSymbs, int accLog)
    {
        int size = 1 << accLog;
        var t = new FseTable();
        t.AccLog = accLog;
        t.Symbols = new byte[size];
        t.NumBits = new byte[size];
        t.Base = new ushort[size];
        var stateDesc = new ushort[256];
        int high = size;
        for (int s = 0; s < numSymbs; s++)
        {
            if (norm[s] == -1) { t.Symbols[--high] = (byte)s; stateDesc[s] = 1; }
        }
        int step = (size >> 1) + (size >> 3) + 3;
        int mask = size - 1;
        int pos = 0;
        for (int s = 0; s < numSymbs; s++)
        {
            if (norm[s] <= 0) continue;
            stateDesc[s] = (ushort)norm[s];
            for (int i = 0; i < norm[s]; i++)
            {
                t.Symbols[pos] = (byte)s;
                do { pos = (pos + step) & mask; } while (pos >= high);
            }
        }
        if (pos != 0) throw new Exception("zstd: bad FSE table");
        for (int i = 0; i < size; i++)
        {
            byte sym = t.Symbols[i];
            int next = stateDesc[sym]++;
            t.NumBits[i] = (byte)(accLog - HighBit((ulong)next));
            t.Base[i] = (ushort)((next << t.NumBits[i]) - size);
        }
        return t;
    }

    static FseTable FseRle(byte sym)
    {
        var t = new FseTable();
        t.AccLog = 0;
        t.Symbols = new byte[] { sym };
        t.NumBits = new byte[] { 0 };
        t.Base = new ushort[] { 0 };
        return t;
    }

    static FseTable FseReadHeader(Fwd f, int maxAcc)
    {
        int accLog = 5 + f.Read(4);
        if (accLog > maxAcc) throw new Exception("zstd: accuracy log too large");
        int remaining = 1 << accLog;
        var freqs = new short[256];
        int symb = 0;
        while (remaining > 0 && symb < 256)
        {
            int bits = HighBit((ulong)(remaining + 1)) + 1;
            int val = f.Read(bits);
            int lowerMask = (1 << (bits - 1)) - 1;
            int threshold = (1 << bits) - 1 - (remaining + 1);
            if ((val & lowerMask) < threshold) { f.Rewind(1); val = val & lowerMask; }
            else if (val > lowerMask) { val = val - threshold; }
            int proba = val - 1;
            remaining -= proba < 0 ? -proba : proba;
            freqs[symb++] = (short)proba;
            if (proba == 0)
            {
                int repeat = f.Read(2);
                while (true)
                {
                    for (int i = 0; i < repeat && symb < 256; i++) freqs[symb++] = 0;
                    if (repeat == 3) repeat = f.Read(2); else break;
                }
            }
        }
        f.Align();
        if (remaining != 0) throw new Exception("zstd: bad FSE header");
        return FseBuild(freqs, symb, accLog);
    }

    // ---- Huffman ----
    static HufTable HufBuild(byte[] bits, int numSymbs)
    {
        int maxBits = 0;
        var rankCount = new int[17];
        for (int i = 0; i < numSymbs; i++) { if (bits[i] > maxBits) maxBits = bits[i]; rankCount[bits[i]]++; }
        int size = 1 << maxBits;
        var t = new HufTable();
        t.MaxBits = maxBits;
        t.Symbols = new byte[size];
        t.NumBits = new byte[size];
        var rankIdx = new int[17];
        rankIdx[maxBits] = 0;
        for (int i = maxBits; i >= 1; i--)
        {
            rankIdx[i - 1] = rankIdx[i] + rankCount[i] * (1 << (maxBits - i));
            for (int k = rankIdx[i]; k < rankIdx[i - 1]; k++) t.NumBits[k] = (byte)i;
        }
        if (rankIdx[0] != size) throw new Exception("zstd: bad huffman table");
        for (int i = 0; i < numSymbs; i++)
        {
            if (bits[i] != 0)
            {
                int code = rankIdx[bits[i]];
                int len = 1 << (maxBits - bits[i]);
                for (int k = 0; k < len; k++) t.Symbols[code + k] = (byte)i;
                rankIdx[bits[i]] += len;
            }
        }
        return t;
    }

    static int ReadHufTable(byte[] src, int p, Ctx ctx)
    {
        int header = src[p++];
        var weights = new byte[256];
        int numSymbs;
        if (header >= 128)
        {
            numSymbs = header - 127;
            int bytes = (numSymbs + 1) / 2;
            for (int i = 0; i < numSymbs; i++)
                weights[i] = (byte)((i % 2 == 0) ? (src[p + i / 2] >> 4) : (src[p + i / 2] & 0xF));
            p += bytes;
        }
        else
        {
            int end = p + header;
            var f = new Fwd(src, p);
            var dt = FseReadHeader(f, 7);
            int bsStart = f.Pos;
            int bsLen = end - bsStart;
            long off = StartOffset(src, bsStart, bsLen);
            ushort s1 = (ushort)StreamRead(src, bsStart, dt.AccLog, ref off);
            ushort s2 = (ushort)StreamRead(src, bsStart, dt.AccLog, ref off);
            numSymbs = 0;
            while (true)
            {
                weights[numSymbs++] = dt.Symbols[s1];
                s1 = (ushort)(dt.Base[s1] + StreamRead(src, bsStart, dt.NumBits[s1], ref off));
                if (off < 0) { weights[numSymbs++] = dt.Symbols[s2]; break; }
                weights[numSymbs++] = dt.Symbols[s2];
                s2 = (ushort)(dt.Base[s2] + StreamRead(src, bsStart, dt.NumBits[s2], ref off));
                if (off < 0) { weights[numSymbs++] = dt.Symbols[s1]; break; }
                if (numSymbs > 255) throw new Exception("zstd: too many huffman weights");
            }
            p = end;
        }
        ulong sum = 0;
        for (int i = 0; i < numSymbs; i++) if (weights[i] > 0) sum += 1UL << (weights[i] - 1);
        int maxBits = HighBit(sum) + 1;
        ulong left = (1UL << maxBits) - sum;
        if ((left & (left - 1)) != 0) throw new Exception("zstd: bad huffman weights");
        int lastW = HighBit(left) + 1;
        var bits = new byte[numSymbs + 1];
        for (int i = 0; i < numSymbs; i++) bits[i] = (byte)(weights[i] > 0 ? (maxBits + 1 - weights[i]) : 0);
        bits[numSymbs] = (byte)(maxBits + 1 - lastW);
        ctx.Huf = HufBuild(bits, numSymbs + 1);
        return p;
    }

    static void HufStream(byte[] src, int start, int len, HufTable t, List<byte> outp)
    {
        long off = StartOffset(src, start, len);
        int mask = (1 << t.MaxBits) - 1;
        int state = (int)StreamRead(src, start, t.MaxBits, ref off);
        while (off > -t.MaxBits)
        {
            outp.Add(t.Symbols[state]);
            int nb = t.NumBits[state];
            int rest = (int)StreamRead(src, start, nb, ref off);
            state = ((state << nb) + rest) & mask;
        }
        if (off != -t.MaxBits) throw new Exception("zstd: huffman stream misaligned");
    }

    static byte[] HufDecode(byte[] src, int p, int end, int regen, int streams, HufTable t)
    {
        var outp = new List<byte>(regen);
        if (streams == 1) HufStream(src, p, end - p, t, outp);
        else
        {
            int s1 = src[p] | (src[p + 1] << 8);
            int s2 = src[p + 2] | (src[p + 3] << 8);
            int s3 = src[p + 4] | (src[p + 5] << 8);
            int q = p + 6;
            int s4 = end - q - s1 - s2 - s3;
            HufStream(src, q, s1, t, outp); q += s1;
            HufStream(src, q, s2, t, outp); q += s2;
            HufStream(src, q, s3, t, outp); q += s3;
            HufStream(src, q, s4, t, outp);
        }
        if (outp.Count != regen) throw new Exception("zstd: literal size mismatch");
        return outp.ToArray();
    }

    // ---- sequences ----
    static FseTable SeqTable(byte[] src, ref int p, int mode, short[] def, int defAcc, int maxAcc, FseTable prev)
    {
        switch (mode)
        {
            case 0: return FseBuild(def, def.Length, defAcc);
            case 1: return FseRle(src[p++]);
            case 2:
                {
                    var f = new Fwd(src, p);
                    var t = FseReadHeader(f, maxAcc);
                    p = f.Pos;
                    return t;
                }
            default:
                if (prev == null) throw new Exception("zstd: repeat table without previous");
                return prev;
        }
    }

    static void DecodeBlock(byte[] src, int p, int size, List<byte> outp, Ctx ctx)
    {
        int end = p + size;
        byte b0 = src[p];
        int litType = b0 & 3;
        int sf = (b0 >> 2) & 3;
        int regen, comp = 0, hdr, streams = 1;
        if (litType == 0 || litType == 1)
        {
            if ((sf & 1) == 0) { regen = b0 >> 3; hdr = 1; }
            else if (sf == 1) { regen = (b0 >> 4) + (src[p + 1] << 4); hdr = 2; }
            else { regen = (b0 >> 4) + (src[p + 1] << 4) + (src[p + 2] << 12); hdr = 3; }
        }
        else
        {
            if (sf == 0 || sf == 1)
            {
                streams = sf == 0 ? 1 : 4;
                long v = b0 | (src[p + 1] << 8) | (src[p + 2] << 16);
                regen = (int)((v >> 4) & 0x3FF); comp = (int)((v >> 14) & 0x3FF); hdr = 3;
            }
            else if (sf == 2)
            {
                streams = 4;
                long v = b0 | (src[p + 1] << 8) | (src[p + 2] << 16) | ((long)src[p + 3] << 24);
                regen = (int)((v >> 4) & 0x3FFF); comp = (int)((v >> 18) & 0x3FFF); hdr = 4;
            }
            else
            {
                streams = 4;
                long v = b0 | (src[p + 1] << 8) | (src[p + 2] << 16) | ((long)src[p + 3] << 24) | ((long)src[p + 4] << 32);
                regen = (int)((v >> 4) & 0x3FFFF); comp = (int)((v >> 22) & 0x3FFFF); hdr = 5;
            }
        }
        p += hdr;
        byte[] lits;
        if (litType == 0) { lits = new byte[regen]; Array.Copy(src, p, lits, 0, regen); p += regen; }
        else if (litType == 1) { lits = new byte[regen]; for (int i = 0; i < regen; i++) lits[i] = src[p]; p += 1; }
        else
        {
            int litEnd = p + comp;
            if (litType == 2) p = ReadHufTable(src, p, ctx);
            else if (ctx.Huf == null) throw new Exception("zstd: treeless literals without table");
            lits = HufDecode(src, p, litEnd, regen, streams, ctx.Huf);
            p = litEnd;
        }

        int nbSeq;
        byte s0 = src[p++];
        if (s0 == 0) nbSeq = 0;
        else if (s0 < 128) nbSeq = s0;
        else if (s0 < 255) nbSeq = ((s0 - 128) << 8) + src[p++];
        else { nbSeq = src[p] + (src[p + 1] << 8) + 0x7F00; p += 2; }

        int litPos = 0;
        if (nbSeq > 0)
        {
            byte modes = src[p++];
            ctx.LL = SeqTable(src, ref p, (modes >> 6) & 3, LL_DEF, 6, 9, ctx.LL);
            ctx.OF = SeqTable(src, ref p, (modes >> 4) & 3, OF_DEF, 5, 8, ctx.OF);
            ctx.ML = SeqTable(src, ref p, (modes >> 2) & 3, ML_DEF, 6, 9, ctx.ML);
            int bsLen = end - p;
            long off = StartOffset(src, p, bsLen);
            int llS = (int)StreamRead(src, p, ctx.LL.AccLog, ref off);
            int ofS = (int)StreamRead(src, p, ctx.OF.AccLog, ref off);
            int mlS = (int)StreamRead(src, p, ctx.ML.AccLog, ref off);
            for (int i = 0; i < nbSeq; i++)
            {
                int ofCode = ctx.OF.Symbols[ofS];
                int llCode = ctx.LL.Symbols[llS];
                int mlCode = ctx.ML.Symbols[mlS];
                if (llCode > 35 || mlCode > 52) throw new Exception("zstd: bad sequence code");
                ulong ofVal = (1UL << ofCode) + StreamRead(src, p, ofCode, ref off);
                ulong ml = ML_BASE[mlCode] + StreamRead(src, p, ML_BITS[mlCode], ref off);
                ulong ll = LL_BASE[llCode] + StreamRead(src, p, LL_BITS[llCode], ref off);
                if (i != nbSeq - 1)
                {
                    llS = ctx.LL.Base[llS] + (int)StreamRead(src, p, ctx.LL.NumBits[llS], ref off);
                    mlS = ctx.ML.Base[mlS] + (int)StreamRead(src, p, ctx.ML.NumBits[mlS], ref off);
                    ofS = ctx.OF.Base[ofS] + (int)StreamRead(src, p, ctx.OF.NumBits[ofS], ref off);
                }
                // resolve offset
                ulong offset;
                ulong[] h = ctx.Rep;
                if (ofVal <= 3)
                {
                    int idx = (int)ofVal - 1;
                    if (ll == 0) idx++;
                    if (idx == 0) offset = h[0];
                    else
                    {
                        offset = idx < 3 ? h[idx] : h[0] - 1;
                        if (idx > 1) h[2] = h[1];
                        h[1] = h[0];
                        h[0] = offset;
                    }
                }
                else
                {
                    offset = ofVal - 3;
                    h[2] = h[1]; h[1] = h[0]; h[0] = offset;
                }
                // execute
                for (ulong k = 0; k < ll; k++) outp.Add(lits[litPos++]);
                int from = outp.Count - (int)offset;
                if (from < 0) throw new Exception("zstd: offset out of range");
                for (ulong k = 0; k < ml; k++) outp.Add(outp[from + (int)k]);
            }
            if (off != 0) throw new Exception("zstd: sequence bitstream not consumed");
        }
        while (litPos < lits.Length) outp.Add(lits[litPos++]);
    }

    static int DecodeFrame(byte[] src, int p, List<byte> outp)
    {
        byte fhd = src[p++];
        int fcsFlag = fhd >> 6;
        bool single = ((fhd >> 5) & 1) == 1;
        bool checksum = ((fhd >> 2) & 1) == 1;
        int dictFlag = fhd & 3;
        if (dictFlag != 0) throw new Exception("zstd: dictionaries not supported");
        if (!single) p++;
        int fcsSize = fcsFlag == 0 ? (single ? 1 : 0) : fcsFlag == 1 ? 2 : fcsFlag == 2 ? 4 : 8;
        p += fcsSize;
        var ctx = new Ctx();
        while (true)
        {
            int bh = src[p] | (src[p + 1] << 8) | (src[p + 2] << 16);
            p += 3;
            bool last = (bh & 1) == 1;
            int type = (bh >> 1) & 3;
            int size = bh >> 3;
            if (type == 0) { for (int i = 0; i < size; i++) outp.Add(src[p + i]); p += size; }
            else if (type == 1) { byte v = src[p]; for (int i = 0; i < size; i++) outp.Add(v); p += 1; }
            else if (type == 2) { DecodeBlock(src, p, size, outp, ctx); p += size; }
            else throw new Exception("zstd: reserved block type");
            if (last) break;
        }
        if (checksum) p += 4;
        return p;
    }

    public static byte[] Decompress(byte[] src)
    {
        var outp = new List<byte>();
        int p = 0;
        while (p + 4 <= src.Length)
        {
            uint magic = BitConverter.ToUInt32(src, p);
            if ((magic & 0xFFFFFFF0u) == 0x184D2A50u)
            {
                uint sz = BitConverter.ToUInt32(src, p + 4);
                p += 8 + (int)sz;
                continue;
            }
            if (magic != 0xFD2FB528u) throw new Exception("zstd: bad magic");
            p = DecodeFrame(src, p + 4, outp);
        }
        return outp.ToArray();
    }
}
