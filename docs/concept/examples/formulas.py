"""SpaceCity 컨셉 문서에서 쓰는 공식 모음.

모든 식은 '게임 밸런스용 근사식'이다. 표준 라이브러리만 사용하며,
직접 실행하면 문서(05-formulas.md)에 인용한 예시 값을 그대로 출력한다.

    python3 docs/concept/examples/formulas.py
"""

import math

# ── 상수 ────────────────────────────────────────────────────────────
G0 = 9.80665                    # 표준 중력가속도 (m/s²)
LY_M = 9.4607304725808e15       # 1광년 (m)
YEAR_S = 31_557_600.0           # 율리우스년 (s)
AU_LIGHT_MIN = 8.316746         # 빛이 1 AU를 지나는 시간 (분)
SUN_LUMINOSITY_W = 3.828e26     # 태양 광도 (W)
SUN_TEFF_K = 5772.0             # 태양 유효온도 (K)
EARTH_ESCAPE_KM_S = 11.186      # 지구 탈출속도 (km/s)
C_M_S = 299_792_458.0           # 광속 (m/s)
STEFAN_BOLTZMANN = 5.670374e-8  # W/(m²·K⁴)
MEGATON_TNT_J = 4.184e15        # TNT 1메가톤 (J)


# ── 항성 ────────────────────────────────────────────────────────────
def star_luminosity(mass):
    """주계열성 질량(태양=1) → 광도(태양=1). 구간별 질량-광도 관계."""
    if mass < 0.43:
        return 0.23 * mass ** 2.3
    if mass < 2.0:
        return mass ** 4
    if mass < 55.0:
        return 1.4 * mass ** 3.5
    return 32_000.0 * mass


def star_radius(mass):
    """주계열성 질량 → 반지름(태양=1). 저질량은 지수 0.9, 고질량은 0.8."""
    return mass ** 0.9 if mass < 1.0 else mass ** 0.8


def star_temperature(mass):
    """슈테판-볼츠만 법칙으로 유효온도(K) 추정: T = T☉ · (L / R²)^¼."""
    return SUN_TEFF_K * (star_luminosity(mass) / star_radius(mass) ** 2) ** 0.25


def main_sequence_lifetime_gyr(mass):
    """주계열 수명(10억 년) ≈ 10 · M / L."""
    return 10.0 * mass / star_luminosity(mass)


# Kopparapu 외(2014) 유효 복사 조도 S_eff 다항식 계수 (지구질량 행성): S☉, a, b, c, d
_HZ_COEFFICIENTS = {
    "recent_venus": (1.776, 2.136e-4, 2.533e-8, -1.332e-11, -3.097e-15),
    "runaway_greenhouse": (1.107, 1.332e-4, 1.580e-8, -8.308e-12, -1.931e-15),
    "maximum_greenhouse": (0.356, 6.171e-5, 1.698e-9, -3.198e-12, -5.575e-16),
    "early_mars": (0.320, 5.547e-5, 1.526e-9, -2.874e-12, -5.011e-16),
}


def _effective_flux(limit, teff_k):
    s_sun, a, b, c, d = _HZ_COEFFICIENTS[limit]
    t = min(max(teff_k, 2600.0), 7200.0) - 5780.0  # 다항식 유효 범위 2600~7200 K
    return s_sun + a * t + b * t ** 2 + c * t ** 3 + d * t ** 4


def habitable_zone_au(luminosity, teff_k=5780.0, optimistic=False):
    """거주가능영역 (내곽, 외곽) AU = √(L / S_eff).

    보수적(기본): 폭주 온실 ~ 최대 온실. 낙관적: '최근의 금성' ~ '초기 화성'.
    S_eff는 항성 온도에 따라 달라서, 붉은 별일수록 같은 광도에서 HZ가 바깥으로 밀린다.
    문헌에서 'HZ 안'이라고 소개되는 적색왜성 행성 중 일부는 낙관적 기준이다.
    """
    inner, outer = (("recent_venus", "early_mars") if optimistic
                    else ("runaway_greenhouse", "maximum_greenhouse"))
    return (math.sqrt(luminosity / _effective_flux(inner, teff_k)),
            math.sqrt(luminosity / _effective_flux(outer, teff_k)))


def frost_line_au(luminosity):
    """설선(얼음선) AU ≈ 2.7 · √L. 이 바깥에서 가스·얼음 행성이 잘 생긴다."""
    return 2.7 * math.sqrt(luminosity)


# ── 행성 ────────────────────────────────────────────────────────────
def orbital_period_days(a_au, star_mass):
    """케플러 제3법칙 P² = a³ / M (P: 년, a: AU, M: 태양질량)."""
    return 365.25 * math.sqrt(a_au ** 3 / star_mass)


def semi_major_axis_au(period_days, star_mass):
    """공전주기(일) → 궤도 장반경(AU). 관측 데이터에 a가 없을 때 쓴다."""
    return ((period_days / 365.25) ** 2 * star_mass) ** (1.0 / 3.0)


def equilibrium_temperature_k(luminosity, a_au, albedo=0.3):
    """복사 평형 온도(K). 지구(L=1, a=1, A=0.3) ≈ 255 K. 온실효과 미포함."""
    return 278.6 * (luminosity * (1.0 - albedo)) ** 0.25 / math.sqrt(a_au)


def surface_gravity_g(mass_earth, radius_earth):
    return mass_earth / radius_earth ** 2


def escape_velocity_km_s(mass_earth, radius_earth):
    return EARTH_ESCAPE_KM_S * math.sqrt(mass_earth / radius_earth)


def is_tidally_locked(a_au, star_mass):
    """게임용 근사: a < 0.3 · M^(1/3) AU 이면 조석 고정으로 본다."""
    return a_au < 0.3 * star_mass ** (1.0 / 3.0)


def earth_similarity_index(radius, density, v_escape, surface_temp_k):
    """지구 유사도 지수 ESI (Schulze-Makuch 외, 2011). 1.0 = 지구.

    radius·density·v_escape는 지구=1 기준, 온도는 K.
    """
    terms = (
        (radius, 1.0, 0.57),
        (density, 1.0, 1.07),
        (v_escape, 1.0, 0.70),
        (surface_temp_k, 288.0, 5.58),
    )
    esi = 1.0
    for value, ref, weight in terms:
        esi *= (1.0 - abs((value - ref) / (value + ref))) ** (weight / len(terms))
    return esi


# ── 문명 · 에너지 ───────────────────────────────────────────────────
def kardashev(power_w):
    """칼 세이건의 연속형 카르다쇼프 지수: K = (log10 P − 6) / 10."""
    return (math.log10(power_w) - 6.0) / 10.0


def drake(r_star, f_p, n_e, f_l, f_i, f_c, lifetime_years):
    """드레이크 방정식: 은하 내 교신 가능한 문명 수 N."""
    return r_star * f_p * n_e * f_l * f_i * f_c * lifetime_years


def detection_range_factor(power_ratio):
    """방출 에너지가 k배면 탐지 거리는 √k배 (역제곱 법칙)."""
    return math.sqrt(power_ratio)


def cultural_distance_factor(delay_years, exchange_halflife_years=5.0):
    """광속 지연 d년인 식민지의 기대 문화 거리 배율 √(1 + d/τ).

    문화 벡터를 평균 회귀 확률과정(OU)으로 두고, 본국과의 교류 강도를
    κ₀ / (1 + d/τ)로 약화시키면 정상 상태 표준편차가 이 비율로 커진다.
    """
    return math.sqrt(1.0 + delay_years / exchange_halflife_years)


# ── 이동 · 공학 ─────────────────────────────────────────────────────
def accel_ly_per_yr2(accel_g):
    """가속도(g) → ly/yr² (광속 c = 1 ly/yr 단위계)."""
    return accel_g * G0 * YEAR_S ** 2 / LY_M


def brachistochrone(distance_ly, accel_g=1.0):
    """중간 지점까지 가속, 이후 감속하는 상대론적 항해.

    반환: (지구 기준 시간[년], 우주선 고유시간[년], 최고 속도 β)
    """
    a = accel_ly_per_yr2(accel_g)
    half = distance_ly / 2.0
    gamma = 1.0 + a * half
    earth_time = 2.0 * math.sqrt(half ** 2 + 2.0 * half / a)
    ship_time = 2.0 * math.acosh(gamma) / a
    beta = math.sqrt(1.0 - 1.0 / gamma ** 2)
    return earth_time, ship_time, beta


def cruise_trip(distance_ly, beta, accel_g=None):
    """순항 속도 β까지 가속 → 관성 비행 → 감속. accel_g=None이면 가감속 무시.

    반환: (지구 기준 시간[년], 우주선 고유시간[년])
    """
    gamma = 1.0 / math.sqrt(1.0 - beta ** 2)
    if accel_g is None:
        earth_time = distance_ly / beta
        return earth_time, earth_time / gamma
    a = accel_ly_per_yr2(accel_g)
    accel_distance = (gamma - 1.0) / a
    if 2.0 * accel_distance >= distance_ly:  # 순항 속도에 닿기 전에 감속해야 함
        earth_time, ship_time, _ = brachistochrone(distance_ly, accel_g)
        return earth_time, ship_time
    coast_time = (distance_ly - 2.0 * accel_distance) / beta
    earth_time = 2.0 * gamma * beta / a + coast_time
    ship_time = 2.0 * math.atanh(beta) / a + coast_time / gamma
    return earth_time, ship_time


def rocket_mass_ratio(delta_v_km_s, isp_s):
    """치올코프스키 로켓 방정식: 질량비 m0/mf = exp(Δv / (Isp·g0))."""
    return math.exp(delta_v_km_s * 1000.0 / (isp_s * G0))


def spin_rpm_for_gravity(radius_m, gravity_g=1.0):
    """반지름 r(m)의 회전체에서 중력 g를 만드는 회전수(rpm)."""
    omega = math.sqrt(gravity_g * G0 / radius_m)
    return omega * 60.0 / (2.0 * math.pi)


def spin_radius_for_gravity(rpm, gravity_g=1.0):
    """회전수 rpm에서 중력 g를 만드는 데 필요한 반지름(m)."""
    omega = rpm * 2.0 * math.pi / 60.0
    return gravity_g * G0 / omega ** 2


def light_delay_minutes(distance_au):
    return distance_au * AU_LIGHT_MIN


def radiator_area_m2(power_w, temp_k, emissivity=0.9):
    """폐열 P를 온도 T로 버리는 데 필요한 방열판 면적(단면): A = P / (εσT⁴)."""
    return power_w / (emissivity * STEFAN_BOLTZMANN * temp_k ** 4)


def launch_energy_mj_per_kg(speed_km_s):
    """질량 1 kg을 속도 v까지 가속하는 에너지 ½v² (MJ/kg). 매스 드라이버 전력 계산용."""
    return 0.5 * (speed_km_s * 1000.0) ** 2 / 1e6


def relativistic_kinetic_energy_j(mass_kg, beta):
    """상대론적 운동 에너지 (γ − 1)mc². 상대론적 운동 에너지 무기(RKV) 위협 계산용."""
    gamma = 1.0 / math.sqrt(1.0 - beta ** 2)
    return (gamma - 1.0) * mass_kg * C_M_S ** 2


# ── 데모: 문서에 인용한 값 출력 ───────────────────────────────────────
def _demo():
    # 한글 폭이 터미널마다 달라 정렬이 깨지므로 숫자를 앞에, 이름을 뒤에 둔다.
    print("[항성] 질량 → 광도 · 반지름 · 온도 · 주계열 수명")
    for name, m in (("적색왜성 M5.5 (프록시마급)", 0.12), ("K2 (엡실론 에리다니급)", 0.82),
                    ("태양", 1.0), ("A1 (시리우스 A급)", 2.06)):
        print(f"  M={m:<5} L={star_luminosity(m):<8.4g} R={star_radius(m):.3f}  "
              f"T={star_temperature(m):>5,.0f} K  수명={main_sequence_lifetime_gyr(m):>6,.1f} Gyr  {name}")

    print("\n[거주가능영역 · 설선] (AU)")
    for name, lum, teff in (("태양", 1.0, 5772), ("프록시마", 0.0016, 3040),
                            ("엡실론 에리다니", 0.34, 5080), ("트라피스트-1", 0.000553, 2570),
                            ("시리우스 A", 25.4, 9940)):
        inner, outer = habitable_zone_au(lum, teff)
        wide_inner, wide_outer = habitable_zone_au(lum, teff, optimistic=True)
        print(f"  HZ {inner:6.3f}–{outer:6.3f}  낙관 {wide_inner:6.3f}–{wide_outer:6.3f}  "
              f"설선 {frost_line_au(lum):6.2f}  {name}")

    print("\n[평형 온도] (반사율 0.3, 온실효과 제외)")
    for name, lum, a in (("지구", 1.0, 1.0), ("화성", 1.0, 1.524),
                         ("프록시마 b", 0.0016, 0.0485), ("트라피스트-1 e", 0.000553, 0.0293)):
        print(f"  {equilibrium_temperature_k(lum, a):4.0f} K  {name}")

    print("\n[ESI]")
    print(f"  {earth_similarity_index(1.0, 1.0, 1.0, 288):.2f}  지구")
    print(f"  {earth_similarity_index(0.532, 0.713, 0.45, 210):.2f}  화성")

    print("\n[카르다쇼프 지수]")
    for name, watts in (("현대 인류 (~19 TW)", 1.9e13), ("지구가 받는 햇빛 전체", 1.74e17),
                        ("태양 광도 전체 (다이슨 스웜 완성)", SUN_LUMINOSITY_W),
                        ("우리 은하 전체 (~10^37 W)", 1e37)):
        print(f"  K = {kardashev(watts):.2f}  {name}")

    print("\n[이동 시간] 프록시마 센타우리 4.25 ly, 가감속 무시")
    for name, beta in (("보이저 1호 (17 km/s)", 17 / 299_792.458), ("0.01c", 0.01),
                       ("0.05c (세대우주선)", 0.05), ("0.12c (다이달로스급)", 0.12),
                       ("0.2c (레이저 돛)", 0.2)):
        earth, _ = cruise_trip(4.25, beta)
        print(f"  {earth:>8,.0f} 년  {name}")
    print("[이동 시간] 1g 가속 → 중간 지점에서 반전 → 1g 감속")
    for target, dist in (("프록시마 4.25 ly", 4.25), ("트라피스트-1 40.7 ly", 40.7),
                         ("은하 중심 26,000 ly", 26_000)):
        earth, ship, beta = brachistochrone(dist, 1.0)
        print(f"  지구 {earth:>9,.1f} 년 / 함내 {ship:4.1f} 년 / 최고 {beta:.4f}c  {target}")
    earth, ship = cruise_trip(5.96, 0.05, accel_g=0.01)
    print(f"  지구 {earth:>9,.0f} 년 / 함내 {ship:4.0f} 년  0.01g 가속·0.05c 순항 → 바너드 별 5.96 ly")

    print("\n[로켓 방정식] 질량비 m0/mf")
    print(f"  {rocket_mass_ratio(9.4, 450):5.2f}  지구 표면 → 저궤도 (Δv 9.4 km/s), 화학 LOX/LH2 Isp 450 s")
    print(f"  {rocket_mass_ratio(9.4, 900):5.2f}  지구 표면 → 저궤도 (Δv 9.4 km/s), 핵열 NTR Isp 900 s")
    print(f"  {rocket_mass_ratio(1.9, 450):5.2f}  달 표면 → 달 저궤도 (Δv 1.9 km/s), 화학")
    print(f"  {(11.19 / 2.38) ** 2:5.1f}  탈출 에너지 비 지구/달 = (11.19 / 2.38)²")

    print("\n[회전 중력]")
    for rpm in (1, 2, 4):
        print(f"  {spin_radius_for_gravity(rpm):>5,.0f} m  1g를 {rpm} rpm으로 만드는 반지름")
    print(f"  {spin_rpm_for_gravity(4000):5.2f} rpm  반지름 4 km 오닐 실린더의 1g 회전수")

    print("\n[광속 지연] (편도)")
    for name, au in (("지구–화성 최근접 0.37 AU", 0.372), ("지구–화성 최원 2.67 AU", 2.67),
                     ("지구–목성 최근접 3.95 AU", 3.95), ("지구–목성 최원 6.45 AU", 6.45)):
        print(f"  {light_delay_minutes(au):5.1f} 분  {name}")

    print("\n[방열판] 폐열 1 GW를 버리는 단면 면적 (방사율 0.9)")
    for temp in (600, 300, 50):
        print(f"  {radiator_area_m2(1e9, temp) / 1e6:>9,.2f} km²  {temp} K")

    print("\n[매스 드라이버] 달 탈출속도 2.38 km/s까지 가속")
    energy = launch_energy_mj_per_kg(2.38)
    print(f"  {energy:.2f} MJ/kg = {energy / 3.6:.2f} kWh/kg (효율 100% 가정)")

    print("\n[상대론적 충돌체] 1톤을 0.1c로")
    joules = relativistic_kinetic_energy_j(1000, 0.1)
    print(f"  {joules:.2e} J ≈ TNT {joules / MEGATON_TNT_J:,.0f} Mt")

    print("\n[드레이크 방정식 프리셋]")
    print(f"  N = {drake(3, 1, 0.4, 1, 0.5, 0.5, 1e6):>9,.0f}  낙관 (R*=3, ne=0.4, fl=1, fi=0.5, fc=0.5, L=10^6)")
    print(f"  N = {drake(1.5, 1, 0.1, 0.01, 0.01, 0.1, 1e4):>9.3f}  희귀 지구 (R*=1.5, ne=0.1, fl=fi=0.01, fc=0.1, L=10^4)")

    print("\n[문화 거리 배율] √(1 + d/τ), τ = 5년")
    for name, delay in (("화성 (지연 ≈ 0)", 0.0), ("프록시마 4.25년", 4.25), ("타우 세티 11.9년", 11.9),
                        ("트라피스트-1 40.7년", 40.7)):
        print(f"  ×{cultural_distance_factor(delay):.2f}  {name}")

    print("\n[탐지 거리] 방출 에너지 k배 → 탐지 거리 √k배")
    print(f"  ×{detection_range_factor(100):,.0f}  에너지 사용 100배")
    print(f"  ×{detection_range_factor(SUN_LUMINOSITY_W / 1.9e13):,.0f}  태양 전체(타입 II) ÷ 현대 인류")


if __name__ == "__main__":
    _demo()
