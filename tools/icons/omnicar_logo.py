"""OmniCar logo (final): ring + CarPlay play slightly bigger than the ring, all three corners
breaking out through it ("every limit"), cosmic-blue gradient. D2 shape, K5 palette."""
COLORS = ("#2563EB", "#0B1026")
CX, CY = 512, 512


def tri_c(g, cx, cy, h, r=26, cut=False):
    w = h * 0.9
    pts = [(-w / 2 + w / 6, -h / 2), (-w / 2 + w / 6, h / 2), (w / 2 + w / 6, 0)]
    g.polygon([(cx + x, cy + y) for x, y in pts], radius=r, cut=cut)


def omnicar(g):
    g.ring(CX, CY, 360, 120)
    tri_c(g, CX, CY, 700, 60, cut=True)
    tri_c(g, CX, CY, 610, 48)


GLYPHS = {"final": omnicar}
