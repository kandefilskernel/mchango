"""Génère les illustrations vectorielles de Mchango (assets/illustrations/*.svg).

Formes simples, couleurs de la marque : légères (quelques Ko), nettes sur tous les écrans.
Relancer après modification :  python -I tool/illustrations.py  (depuis apps/mobile)
"""
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "illustrations")

# Couleurs de la marque (identiques à lib/ui/theme.dart)
GREEN = "#0F5E43"
GREEN_LIGHT = "#2E8B57"
MINT = "#E3F1EA"
GOLD = "#F2B33D"
GOLD_DARK = "#C98A1B"
INK = "#1F2933"
SKY = "#FFF8EC"

SKINS = ["#5C3A21", "#7A4A2A", "#8D5524", "#6B4226", "#A0662F"]
CLOTHES = ["#E4572E", "#3B82C4", "#8E44AD", "#17A589", "#D35400"]
WRAPS = ["#F2B33D", "#E4572E", "#17A589", "#3B82C4", "#8E44AD"]


def svg(width, height, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
            f'width="{width}" height="{height}">\n{body}\n</svg>\n')


def give_hand(x, y, scale=1.0, side=1):
    """Position de la main tendue d'un personnage en pose « give »."""
    return x + 33 * scale * side, y - 44 * scale


def person(x, y, skin, cloth, wrap=None, scale=1.0, arms="down", side=1):
    """Personnage debout ; (x, y) = milieu des pieds. side : 1 tend la main à droite, -1 à gauche."""
    s = scale
    def p(dx, dy):
        return f"{x + dx * s:.1f} {y + dy * s:.1f}"
    parts = [
        # jambes
        f'<rect x="{x - 11 * s:.1f}" y="{y - 24 * s:.1f}" width="{8 * s:.1f}" height="{24 * s:.1f}" rx="{3 * s:.1f}" fill="{INK}"/>',
        f'<rect x="{x + 3 * s:.1f}" y="{y - 24 * s:.1f}" width="{8 * s:.1f}" height="{24 * s:.1f}" rx="{3 * s:.1f}" fill="{INK}"/>',
        # corps
        f'<path d="M {p(-16, -62)} Q {p(0, -70)} {p(16, -62)} L {p(21, -20)} Q {p(0, -14)} {p(-21, -20)} Z" fill="{cloth}"/>',
    ]
    # bras
    if arms == "up":
        parts += [f'<path d="M {p(-14, -58)} L {p(-26, -86)}" stroke="{cloth}" stroke-width="{7 * s:.1f}" stroke-linecap="round"/>',
                  f'<path d="M {p(14, -58)} L {p(26, -86)}" stroke="{cloth}" stroke-width="{7 * s:.1f}" stroke-linecap="round"/>',
                  f'<circle cx="{x - 27 * s:.1f}" cy="{y - 89 * s:.1f}" r="{4.5 * s:.1f}" fill="{skin}"/>',
                  f'<circle cx="{x + 27 * s:.1f}" cy="{y - 89 * s:.1f}" r="{4.5 * s:.1f}" fill="{skin}"/>']
    elif arms == "give":  # un bras tendu vers le centre de la scène, l'autre le long du corps
        hx, hy = give_hand(x, y, s, side)
        parts += [f'<path d="M {p(-14 * side, -58)} L {p(-20 * side, -32)}" stroke="{cloth}" stroke-width="{7 * s:.1f}" stroke-linecap="round"/>',
                  f'<circle cx="{x - 20 * s * side:.1f}" cy="{y - 29 * s:.1f}" r="{4.5 * s:.1f}" fill="{skin}"/>',
                  f'<path d="M {p(14 * side, -58)} L {p(30 * side, -46)}" stroke="{cloth}" stroke-width="{7 * s:.1f}" stroke-linecap="round"/>',
                  f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="{4.5 * s:.1f}" fill="{skin}"/>']
    else:
        parts += [f'<path d="M {p(-15, -58)} L {p(-20, -30)}" stroke="{cloth}" stroke-width="{7 * s:.1f}" stroke-linecap="round"/>',
                  f'<path d="M {p(15, -58)} L {p(20, -30)}" stroke="{cloth}" stroke-width="{7 * s:.1f}" stroke-linecap="round"/>',
                  f'<circle cx="{x - 20 * s:.1f}" cy="{y - 27 * s:.1f}" r="{4.5 * s:.1f}" fill="{skin}"/>',
                  f'<circle cx="{x + 20 * s:.1f}" cy="{y - 27 * s:.1f}" r="{4.5 * s:.1f}" fill="{skin}"/>']
    # cou + tête
    parts += [f'<rect x="{x - 4 * s:.1f}" y="{y - 70 * s:.1f}" width="{8 * s:.1f}" height="{8 * s:.1f}" fill="{skin}"/>',
              f'<circle cx="{x:.1f}" cy="{y - 80 * s:.1f}" r="{13 * s:.1f}" fill="{skin}"/>']
    if wrap:  # foulard / liputa
        parts.append(f'<path d="M {p(-14, -82)} Q {p(-16, -102)} {p(0, -104)} Q {p(18, -104)} {p(14, -82)} Q {p(0, -90)} {p(-14, -82)} Z" fill="{wrap}"/>')
        parts.append(f'<circle cx="{x + 13 * s:.1f}" cy="{y - 98 * s:.1f}" r="{4 * s:.1f}" fill="{wrap}"/>')
    else:
        parts.append(f'<path d="M {p(-13, -82)} Q {p(-12, -95)} {p(0, -94)} Q {p(12, -95)} {p(13, -82)} Q {p(0, -88)} {p(-13, -82)} Z" fill="{INK}"/>')
    return "\n".join(parts)


def coin(x, y, r=8, opacity=1.0):
    return (f'<g opacity="{opacity}"><circle cx="{x}" cy="{y}" r="{r}" fill="{GOLD}" stroke="{GOLD_DARK}" stroke-width="{r * 0.25:.1f}"/>'
            f'<circle cx="{x}" cy="{y}" r="{r * 0.5:.1f}" fill="none" stroke="{GOLD_DARK}" stroke-width="{r * 0.15:.1f}"/></g>')


def pot(x, y, w=70, fill_level=0.0):
    """Marmite commune ; (x, y) = haut du bord. fill_level 0..1 : pièces visibles."""
    h = w * 0.62
    parts = [f'<ellipse cx="{x}" cy="{y + h + 4}" rx="{w * 0.55:.1f}" ry="6" fill="{INK}" opacity="0.12"/>',
             f'<path d="M {x - w / 2} {y} Q {x - w / 2 - 6} {y + h} {x} {y + h} Q {x + w / 2 + 6} {y + h} {x + w / 2} {y} Z" fill="{GREEN}"/>',
             f'<ellipse cx="{x}" cy="{y}" rx="{w / 2 + 4:.1f}" ry="9" fill="{GREEN_LIGHT}"/>']
    if fill_level > 0:
        for i, dx in enumerate([-18, -6, 6, 18, -12, 0, 12][: max(1, int(7 * fill_level))]):
            parts.append(coin(x + dx, y - 2 - (6 if i >= 4 else 0), 7))
    parts.append(f'<path d="M {x - w / 2 - 6} {y + 8} q -10 2 -8 12" stroke="{GREEN}" stroke-width="5" fill="none" stroke-linecap="round"/>')
    parts.append(f'<path d="M {x + w / 2 + 6} {y + 8} q 10 2 8 12" stroke="{GREEN}" stroke-width="5" fill="none" stroke-linecap="round"/>')
    return "\n".join(parts)


def moto(x, y, color=GREEN_LIGHT, s=1.0):
    """Moto-taxi ; (x, y) = sol sous la roue arrière."""
    def p(dx, dy):
        return f"{x + dx * s:.1f} {y + dy * s:.1f}"
    return "\n".join([
        f'<circle cx="{x:.1f}" cy="{y - 14 * s:.1f}" r="{14 * s:.1f}" fill="{INK}"/>',
        f'<circle cx="{x:.1f}" cy="{y - 14 * s:.1f}" r="{6 * s:.1f}" fill="#9AA5B1"/>',
        f'<circle cx="{x + 64 * s:.1f}" cy="{y - 14 * s:.1f}" r="{14 * s:.1f}" fill="{INK}"/>',
        f'<circle cx="{x + 64 * s:.1f}" cy="{y - 14 * s:.1f}" r="{6 * s:.1f}" fill="#9AA5B1"/>',
        f'<path d="M {p(0, -14)} L {p(22, -30)} L {p(46, -30)} L {p(64, -14)}" stroke="#52606D" stroke-width="{4 * s:.1f}" fill="none"/>',
        f'<path d="M {p(14, -34)} Q {p(30, -48)} {p(50, -36)} L {p(46, -26)} L {p(18, -26)} Z" fill="{color}"/>',
        f'<rect x="{x + 10 * s:.1f}" y="{y - 42 * s:.1f}" width="{24 * s:.1f}" height="{7 * s:.1f}" rx="{3 * s:.1f}" fill="{INK}"/>',
        f'<path d="M {p(48, -36)} L {p(58, -56)} L {p(66, -56)}" stroke="#52606D" stroke-width="{4 * s:.1f}" fill="none" stroke-linecap="round"/>',
        f'<circle cx="{x + 60 * s:.1f}" cy="{y - 44 * s:.1f}" r="{4 * s:.1f}" fill="{GOLD}"/>',
    ])


def kiosk(x, y, w=86, h=74):
    """Petite boutique ; (x, y) = coin bas gauche."""
    stripes = "".join(
        f'<rect x="{x + i * w / 6:.1f}" y="{y - h - 4}" width="{w / 6:.1f}" height="16" fill="{GOLD if i % 2 == 0 else "#FFFFFF"}"/>'
        for i in range(6))
    return "\n".join([
        f'<rect x="{x}" y="{y - h}" width="{w}" height="{h}" rx="4" fill="#FFFFFF" stroke="{GREEN}" stroke-width="3"/>',
        stripes,
        f'<path d="M {x} {y - h + 12} ' + " ".join(f"q {w / 12:.1f} 10 {w / 6:.1f} 0" for _ in range(6)) + f'" fill="{GOLD}" stroke="{GOLD_DARK}" stroke-width="1.5"/>',
        f'<rect x="{x + 8}" y="{y - h + 26}" width="{w - 16}" height="{h * 0.42:.1f}" rx="3" fill="{MINT}"/>',
        f'<rect x="{x + 14}" y="{y - h + 32}" width="12" height="16" rx="2" fill="#E4572E"/>',
        f'<rect x="{x + 30}" y="{y - h + 36}" width="12" height="12" rx="2" fill="#3B82C4"/>',
        f'<rect x="{x + 46}" y="{y - h + 30}" width="12" height="18" rx="2" fill="{GREEN_LIGHT}"/>',
        f'<rect x="{x + 62}" y="{y - h + 34}" width="10" height="14" rx="2" fill="{GOLD}"/>',
        f'<rect x="{x - 4}" y="{y - 10}" width="{w + 8}" height="10" rx="3" fill="{GREEN}"/>',
    ])


def ground(width, y):
    return f'<rect x="0" y="{y}" width="{width}" height="6" rx="3" fill="{GREEN}" opacity="0.15"/>'


def backdrop(width, height, cx, cy, r):
    return (f'<rect width="{width}" height="{height}" fill="{SKY}"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{MINT}"/>')


# ---------- 1. Seul, c'est long ----------
def scene_alone():
    W, H = 360, 280
    body = [backdrop(W, H, 180, 140, 120), ground(W, 236)]
    # le projet, lointain et pâle
    body.append(f'<g opacity="0.28">{moto(250, 118, s=0.8)}</g>')
    body.append(f'<path d="M 92 220 C 150 210 170 150 240 124" stroke="{GREEN}" stroke-width="3" stroke-dasharray="2 9" stroke-linecap="round" fill="none" opacity="0.6"/>')
    # calendrier : les mois passent
    for i, (cx, cy) in enumerate([(150, 70), (176, 62), (202, 70)]):
        body.append(f'<g opacity="{0.35 + i * 0.2:.2f}"><rect x="{cx - 12}" y="{cy - 12}" width="24" height="26" rx="4" fill="#FFFFFF" stroke="{INK}" stroke-width="2"/>'
                    f'<rect x="{cx - 12}" y="{cy - 12}" width="24" height="8" rx="3" fill="#E4572E"/></g>')
    body.append(person(78, 236, SKINS[2], CLOTHES[0], WRAPS[0]))
    # petite tirelire presque vide
    body.append(f'<rect x="108" y="206" width="30" height="30" rx="8" fill="#FFFFFF" stroke="{GREEN}" stroke-width="3"/>')
    body.append(coin(123, 226, 6))
    return svg(W, H, "\n".join(body))


# ---------- 2. Ensemble, on cotise ----------
def scene_together():
    W, H = 360, 280
    body = [backdrop(W, H, 180, 150, 125), ground(W, 248)]
    body.append(pot(180, 196, 84, fill_level=0.0))
    # Le bénéficiaire du tour, au fond, se réjouit
    body.append(person(180, 158, SKINS[4], CLOTHES[4], None, scale=0.78, arms="up"))
    # Quatre membres tendent leur cotisation vers la marmite commune
    givers = [(52, 240, 0, 1), (112, 216, 1, 1), (248, 216, 2, -1), (308, 240, 3, -1)]
    targets = [(160, 188), (170, 182), (190, 182), (200, 188)]
    for (x, y, k, side), (tx, ty) in zip(givers, targets):
        body.append(person(x, y, SKINS[k], CLOTHES[k], WRAPS[k] if k % 2 == 0 else None,
                           scale=0.92, arms="give", side=side))
        hx, hy = give_hand(x, y, 0.92, side)
        cx, cy = hx + 4 * side, hy - 8
        mx, my = (cx + tx) / 2, min(cy, ty) - 34
        body.append(f'<path d="M {cx:.1f} {cy:.1f} Q {mx:.1f} {my:.1f} {tx} {ty}" stroke="{GOLD_DARK}" '
                    f'stroke-width="2" stroke-dasharray="3 6" fill="none" opacity="0.7"/>')
        body.append(coin(round(cx, 1), round(cy, 1), 8))
    body.append(coin(180, 176, 9))
    body.append(coin(170, 186, 7, 0.9))
    body.append(coin(192, 186, 7, 0.9))
    return svg(W, H, "\n".join(body))


# ---------- 3. À chaque tour, un membre reçoit tout ----------
def scene_project():
    W, H = 360, 280
    body = [backdrop(W, H, 180, 140, 125)]
    # rayons de soleil
    for i in range(12):
        body.append(f'<rect x="178" y="26" width="4" height="22" rx="2" fill="{GOLD}" opacity="0.5" '
                    f'transform="rotate({i * 30} 180 140) translate(0 -8)"/>')
    body.append(ground(W, 240))
    body.append(kiosk(214, 240))
    body.append(moto(36, 240, color=GREEN_LIGHT, s=1.05))
    body.append(person(170, 240, SKINS[2], CLOTHES[0], WRAPS[0], arms="up"))
    # pièces / confettis
    for (x, y, r) in [(126, 70, 7), (232, 64, 6), (110, 120, 5), (262, 106, 6), (150, 46, 5), (212, 40, 5)]:
        body.append(coin(x, y, r))
    return svg(W, H, "\n".join(body))


# ---------- 4. Tout est vérifiable ----------
def scene_verified():
    W, H = 360, 280
    body = [backdrop(W, H, 180, 140, 120)]
    # téléphone
    body.append(f'<rect x="118" y="34" width="124" height="214" rx="18" fill="{INK}"/>')
    body.append(f'<rect x="126" y="50" width="108" height="184" rx="8" fill="#FFFFFF"/>')
    body.append(f'<rect x="162" y="40" width="36" height="5" rx="2.5" fill="#52606D"/>')
    for i in range(5):
        y = 66 + i * 32
        body.append(f'<circle cx="144" cy="{y + 8}" r="9" fill="{GREEN_LIGHT}"/>'
                    f'<path d="M 139 {y + 8} l 4 4 l 7 -8" stroke="#FFFFFF" stroke-width="2.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
                    f'<rect x="160" y="{y + 2}" width="{58 - (i % 3) * 10}" height="6" rx="3" fill="{INK}" opacity="0.75"/>'
                    f'<rect x="160" y="{y + 11}" width="{40 + (i % 2) * 12}" height="5" rx="2.5" fill="{INK}" opacity="0.25"/>')
    # chaîne (journal chaîné) : maillons qui se recouvrent
    for i in range(4):
        cy = 74 + i * 27
        body.append(f'<rect x="262" y="{cy}" width="24" height="36" rx="12" fill="none" stroke="{GOLD_DARK}" stroke-width="5"/>')
    # bouclier
    body.append(f'<path d="M 72 98 L 104 86 L 104 124 Q 104 150 72 164 Q 40 150 40 124 L 40 86 Z" fill="{GREEN}" transform="translate(-6 0)"/>')
    body.append(f'<path d="M 52 124 l 11 11 l 21 -24" stroke="{GOLD}" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round" transform="translate(-6 0)"/>')
    return svg(W, H, "\n".join(body))


# ---------- Logo : cinq membres autour d'une pièce ----------
def logo():
    import math
    parts = [f'<circle cx="64" cy="64" r="64" fill="{GREEN}"/>']
    for i in range(5):
        a = -math.pi / 2 + i * 2 * math.pi / 5
        x, y = 64 + 38 * math.cos(a), 64 + 38 * math.sin(a)
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="11" fill="#FFFFFF"/>')
        # trait vers le centre : la contribution
        x2, y2 = 64 + 22 * math.cos(a), 64 + 22 * math.sin(a)
        parts.append(f'<path d="M {x:.1f} {y:.1f} L {x2:.1f} {y2:.1f}" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" opacity="0.6"/>')
    parts.append(f'<circle cx="64" cy="64" r="17" fill="{GOLD}" stroke="{GOLD_DARK}" stroke-width="3"/>')
    parts.append(f'<circle cx="64" cy="64" r="8" fill="none" stroke="{GOLD_DARK}" stroke-width="2.5"/>')
    return svg(128, 128, "\n".join(parts))


def main():
    os.makedirs(OUT, exist_ok=True)
    files = {
        "seul.svg": scene_alone(),
        "ensemble.svg": scene_together(),
        "projet.svg": scene_project(),
        "verifie.svg": scene_verified(),
        "logo.svg": logo(),
    }
    for name, content in files.items():
        with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        print(f"{name}: {len(content)} octets")


if __name__ == "__main__":
    sys.exit(main())
