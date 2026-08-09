# R0 MobileNetV2 allocation evidence

The R0 quick run records actual Metal resource allocation alongside logical
payload bytes. It is a reproducibility/control artifact, not a final headline
benchmark.

Artifact: `benchmarks/results/r0-mobilenetv2-quick.json`

| Resource | Value |
| --- | ---: |
| B logical RGBA32Float intermediate payload | 802,816 bytes |
| B Metal RGBA32Float intermediate allocation | 819,200 bytes |
| B activation Metal allocation | 2,408,448 bytes |
| C activation Metal allocation | 2,408,448 bytes |
| C logical RGBA32Float intermediate payload | 0 bytes |

The run used the expanded 32-input corpus, five warmups, 20 measured
iterations, and passed B/C parity and independent source-derived checks. The
logical payload and runtime allocation are deliberately reported as separate
quantities.
