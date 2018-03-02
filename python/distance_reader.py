import struct

def readstruct(f, s, n=None):
    if n:
        return s.iter_unpack(f.read(s.size * n))
    else:
        return s.unpack(f.read(s.size))

class DistanceReader:
    S_IDX_NUM_SYNSETS = struct.Struct('=i')
    S_IDX_SYNSET = struct.Struct('=icq')

    S_DIST_HEADER = struct.Struct('=ici')
    S_DIST_DISTS = struct.Struct('=icf')

    def __init__(self, dist_file, index_file):
        self.dist_file = dist_file
        self.index = {}
        with open(index_file, 'rb') as f:
            num_synsets, = readstruct(f, self.S_IDX_NUM_SYNSETS)
            for synset_idx in range(num_synsets):
                offset, pos, loc = readstruct(f, self.S_IDX_SYNSET)
                self.index[pos.decode('us-ascii'), offset] = loc

    def __getitem__(self, pos_offset):
        pos, offset = pos_offset
        loc = self.index[pos, offset]
        result = { pos_offset: 0 }
        with open(self.dist_file, "rb") as f:
            f.seek(loc)
            r_offset, r_pos, num_dists = readstruct(f, self.S_DIST_HEADER)
            for target_offset, target_pos, dist in readstruct(f, self.S_DIST_DISTS, num_dists):
                result[pos, target_offset] = dist
        return result

    @staticmethod
    def to(dist, pos, offset):
        try:
            return dist[pos, offset]
        except KeyError:
            return float('inf')




if __name__ == '__main__':
    import os.path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dr = DistanceReader(script_dir + "/../distances.bin", script_dir + "/../distances.idx")

    from nltk.corpus import wordnet as wn

    while True:
        w1 = input("W1: ")
        w1s = wn.synsets(w1)
        if w1s:
            break
        else:
            print("Unknown word, please enter again")
    while True:
        w2 = input("W2: ")
        w2s = wn.synsets(w2)
        if w2s:
            break
        else:
            print("Unknown word, please enter again")

    results = []
    for s1 in w1s:
        try:
            dt = dr[s1.pos(), s1.offset()]
            for s2 in w2s:
                d = dr.to(dt, s2.pos(), s2.offset())
                results.append((d, s1, s2))
        except KeyError:
            print("No record of distances for %s" % s1)
    results.sort()
    for dist, s1, s2 in results:
        print("%s\n%s\n%s\n" % (dist, s1.definition(), s2.definition()))
