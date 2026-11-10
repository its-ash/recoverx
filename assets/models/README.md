# Sensitive-content model

`nsfw_mobilenet_v2_224.tflite` is the MobileNetV2 (140, 224) NSFW classifier
from [GantMan/nsfw_model](https://github.com/GantMan/nsfw_model), release
1.2.0 (`mobilenet_v2_140_224.1.zip`, file `saved_model.tflite`). MIT licence.

- Input: `1 × 224 × 224 × 3` float32, RGB, values scaled to `0..1`.
- Output: `1 × 5` softmax in this order: `drawings, hentai, neutral, porn, sexy`.
- Reported validation accuracy: about 92 %.
- SHA-256: `380f98f7685f9d8a386f8cc595b6dfcb972989aae3d1b8b270d3a4a5b96fab40`

It flags items for human review. It is not proof, and it is not a CSAM detector.
