import struct

def readstruct(f, s, n=None):
    if n:
        return s.iter_unpack(f.read(s.size * n))
    else:
        return s.unpack(f.read(s.size))

class DistanceReader:
    S_IDX_NUM_POS = struct.Struct('=i')
    S_IDX_POS_HEADER = struct.Struct('=ci')
    S_IDX_DISTS = struct.Struct('=iq')

    S_DIST_HEADER = struct.Struct('=ici')
    S_DIST_DISTS = struct.Struct('=icf')

    def __init__(self, dist_file, index_file):
        self.dist_file = dist_file
        self.index = {}
        with open(index_file, 'rb') as f:
            num_pos, = readstruct(f, self.S_IDX_NUM_POS)
            for pos_idx in range(num_pos):
                pos, num_off = readstruct(f, self.S_IDX_POS_HEADER)
                d = self.index[pos.decode('us-ascii')] = {}
                for offset, loc in readstruct(f, self.S_IDX_DISTS, num_off):
                    d[offset] = loc

    def __getitem__(self, pos_offset):
        pos, offset = pos_offset
        loc = self.index[pos][offset]
        result = {}
        with open(self.dist_file, "rb") as f:
            f.seek(loc)
            r_offset, r_pos, num_dists = readstruct(f, self.S_DIST_HEADER)
            for target_offset, target_pos, dist in readstruct(f, self.S_DIST_DISTS, num_dists):
                result[pos, target_offset] = dist
        return result



if __name__ == '__main__':
    import os.path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dr = DistanceReader(script_dir + "/../distances.bin", script_dir + "/../distances.idx")
    print("Distance between coffee#1 and coffee_substitute#1: %s" % dr['n', 7945759]['n', 7897775])