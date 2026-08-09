# Phase 2 primary references

Use primary Apple documentation and original papers before secondary blog posts.

## Current stable-toolchain opportunities

- `MLMultiArray` overview and creation methods: https://developer.apple.com/documentation/coreml/mlmultiarray
- Buffer-backed multiarray initializer: https://developer.apple.com/documentation/coreml/mlmultiarray/init%28datapointer%3Ashape%3Adatatype%3Astrides%3Adeallocator%3A%29
- IOSurface-backed Float16 multiarray: https://developer.apple.com/documentation/coreml/mlmultiarray/init%28pixelbuffer%3Ashape%3A%29
- CVPixelBuffer plane to live Metal texture: https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage
- Metal tensor: https://developer.apple.com/documentation/metal/mtltensor
- Metal tensor descriptor: https://developer.apple.com/documentation/metal/mtltensordescriptor
- WWDC25 Metal 4 ML command encoder and MTLPackage workflow: https://developer.apple.com/videos/play/wwdc2025/262/
- Metal 4 ML pipeline state: https://developer.apple.com/documentation/metal/mtl4machinelearningpipelinestate

## Optional beta frontier

- Core AI overview: https://developer.apple.com/documentation/coreai
- Core AI inference function: https://developer.apple.com/documentation/coreai/inferencefunction
- Core AI NDArray raw view: https://developer.apple.com/documentation/coreai/ndarray/rawview
- WWDC26 Core AI model authoring/custom Metal kernels: https://developer.apple.com/videos/play/wwdc2026/325/
- WWDC26 Metal tensors/TensorOps: https://developer.apple.com/videos/play/wwdc2026/330/
- Core AI Debugger requirements: https://developer.apple.com/core-ai-debugger/
- Xcode system requirements: https://developer.apple.com/xcode/system-requirements/

## Core ML model format

- Convert to ML Program: https://apple.github.io/coremltools/docs-guides/source/convert-to-ml-program.html
- Source/target conversion formats: https://apple.github.io/coremltools/docs-guides/source/target-conversion-formats.html
- MIL overview: https://apple.github.io/coremltools/docs-guides/source/model-intermediate-language.html

## Adjacent research and prior art

- Learning Sensor Multiplexing Design through Back-propagation: https://arxiv.org/abs/1605.07078
- Deep Camera: https://openaccess.thecvf.com/content_ICCVW_2019/html/LCI/Ratnasingam_Deep_Camera_A_Fully_Convolutional_Neural_Network_for_Image_Signal_ICCVW_2019_paper.html
- Learned Hierarchical B-frame Coding for YUV 4:2:0: https://arxiv.org/abs/2212.14187
- DeltaCNN: https://openaccess.thecvf.com/content/CVPR2022/html/Parger_DeltaCNN_End-to-End_CNN_Inference_of_Sparse_Frame_Differences_in_Videos_CVPR_2022_paper.html
- MotionDeltaCNN: https://openaccess.thecvf.com/content/ICCV2023/html/Parger_MotionDeltaCNN_Sparse_CNN_Inference_of_Frame_Differences_in_Moving_Camera_Videos_with_Spherical_Buffers_ICCV_2023_paper.html
