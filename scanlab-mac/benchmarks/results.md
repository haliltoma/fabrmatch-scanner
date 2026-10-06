# M26 benchmark — sabit hat (ajansız taban çizgisi)

Yazıcı: Creality K2 Pro 0.4, PLA · sapma bütçesi 0.3 mm · tarama: 0,05 mm gürültü, 4 boşluk, 2 kopuk parça

| part | holes_before | components_before | steps | watertight | components | dev_raw_p95 | dev_truth_p95 | dev_truth_max | volume_err_pct | printable | warnings | slice_ok | print_time | filament_g |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| flat_plate | 4 | 3 | components → fill → normals → orient → flatten_base | True | 1 | 0.12083 | 0.07907 | 0.14222 | 1.97 | True | [] | True | 22m 28s | 10.69 |
| holed_bracket | 4 | 3 | components → fill → normals → orient → flatten_base | True | 1 | 0.10283 | 0.07738 | 0.16131 | 0.97 | True | ['overhangs'] | True | 33m 41s | 11.2 |
| stepped_shaft | 4 | 3 | components → fill → normals → orient → flatten_base | True | 1 | 0.05027 | 0.07974 | 0.33191 | 0.18 | True | [] | True | 50m 37s | 8.04 |
| thin_walled_box | 4 | 3 | components → fill → normals → orient → flatten_base | True | 1 | 0.09573 | 0.07895 | 0.17903 | 1.84 | True | [] | True | 24m 48s | 8.98 |
| organic_handle | 4 | 3 | components → fill → normals → orient → flatten_base | True | 1 | 0.23149 | 0.24719 | 0.38419 | 0.56 | True | ['overhangs'] | True | 27m 57s | 10.08 |

**Geçen: 5/5** (watertight + manifold + tek gövde + dilimleme + bütçe)
