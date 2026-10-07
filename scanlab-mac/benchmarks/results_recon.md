# Yeniden yapılandırma benchmark'ı

Sentetik taramalar (masa, mesafeye bağlı gürültü, uçan pikseller, sıyırma kaybı, poz hatası). Gerçek F-skoru eşiği: LiDAR 2.0 mm, TrueDepth 0.5 mm.

## Seçici

| sensör | parça | seçilen | F (CAD) | chamfer mm | en iyi (CAD) | F | pişmanlık |
|---|---|---|---|---|---|---|---|
| truedepth | flat_plate | tsdf_poisson_0.5mm | 0.9999 | 0.068 | tsdf_poisson_0.5mm | 0.9999 | 0.0 |
| truedepth | holed_bracket | tsdf_poisson_0.5mm | 0.9871 | 0.125 | tsdf_poisson_0.5mm | 0.9871 | 0.0 |
| truedepth | stepped_shaft | tsdf_poisson_0.5mm | 0.9978 | 0.148 | tsdf_poisson_0.5mm | 0.9978 | 0.0 |
| truedepth | thin_walled_box | tsdf_poisson_0.5mm | 0.9891 | 0.148 | tsdf_poisson_0.5mm | 0.9891 | 0.0 |
| truedepth | organic_handle | tsdf_poisson_0.5mm | 0.698 | 0.986 | poisson_d9 | 0.7062 | 0.0082 |

**İyi seçim (pişmanlık ≤ 0.02): 5/5**

## Algoritmaların CAD'e F-skoru (kör: ayrılmış karelerde derinlik RMSE, mm)

| sensör | parça | ball_pivoting | poisson_d10 | poisson_d8 | poisson_d9 | tsdf_0.5mm | tsdf_1mm | tsdf_2mm | tsdf_poisson_0.5mm |
|---|---|---|---|---|---|---|---|---|---|
| truedepth | flat_plate | hata | 0.9439 (0.832) | 0.9588 (0.8059) | 0.9241 (0.8417) | 0.6246 (0.8098) | 0.8963 (0.82) | 0.905 (0.8964) | 0.9999 (0.8049) |
| truedepth | holed_bracket | hata | 0.9197 (0.9804) | 0.9135 (0.9939) | 0.9113 (1.0034) | 0.7656 (0.8247) | 0.946 (0.8299) | 0.3838 (1.1541) | 0.9871 (0.7941) |
| truedepth | stepped_shaft | hata | 0.9638 (0.8739) | 0.9585 (0.878) | 0.9604 (0.8792) | 0.9818 (0.8528) | 0.9724 (0.8623) | 0.8172 (1.0261) | 0.9978 (0.844) |
| truedepth | thin_walled_box | hata | 0.864 (1.0491) | 0.8642 (1.0641) | 0.8635 (1.0502) | 0.8046 (1.1337) | 0.3395 (1.7143) | 0.2074 (1.9472) | 0.9891 (0.9039) |
| truedepth | organic_handle | hata | 0.6816 (1.4042) | 0.6918 (1.3916) | 0.7062 (1.396) | 0.5975 (1.4319) | 0.567 (1.4087) | 0.5319 (1.4793) | 0.698 (1.3676) |
