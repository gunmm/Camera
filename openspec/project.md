# 项目上下文

## 用途 (Purpose)
Camera 是一款 iOS 平台的相机应用，专门提供特定场景（如拍摄月亮、拍摄星星）专属拍摄体验。它通过自定相机硬件参数（如曝光时间、对焦、ISO 锁定）以及实时图像预览处理（基于 CIImage 滤镜增强），使得用户能够更轻松地捕获夜星影像。

## 技术栈 (Tech Stack)
- **核心语言**: Swift
- **UI框架**: UIKit (纯代码控制构建，无 Storyboard)
- **相机底层 API**: AVFoundation (AVCaptureSession, AVCaptureDevice)
- **图像处理引擎**: CoreImage (CIContext, CIFilter) 以及 Vision
- **图形渲染引擎**: Metal (基于 `PreviewMetalView` 的高性能实时画面渲染)
- **支持平台**: iOS
- **相册存储**: Photos (PHPhotoLibrary)

## 项目约定 (Project Conventions)

### 代码风格 (Code Style)
- **命名规范**: 遵循标准 Swift API Design Guidelines
- **项目组织结构**: 
  - 视图控制器 (如 `ViewController`) 主要处理 UI 交互与路由
  - 核心业务逻辑剥离为管理类（如 `CameraManager`, `ImageProcessor`），以便责任清晰、逻辑专注。

### 架构模式 (Architecture Patterns)
- **Manager 封装模式**: 
  - `CameraManager` 封装底层 AVFoundation 会话配置与硬件设备参数的锁定逻辑。
  - `ImageProcessor` 集中处理 CoreImage 滤镜与图像增强逻辑。
- **Delegate 委托模式**: 
  - 采用 Delegate 协议（如 `CameraManagerDelegate`）完成层级与对象间的视频帧 `CMSampleBuffer` 回调。

### 开发工作流 (Development Workflow)
- **依赖管理**: 项目目前无外部庞大第三方库依赖，开发均依赖 iOS 原生框架支撑。

## 领域上下文 (Domain Context)
- **相机底层控制**: 需要深入理解 `AVCaptureDevice` 的底层设定。包括使用 `lockForConfiguration` 进行设备参数锁定机制，并掌握如何直接控制 ISO 曝光参数 (`setExposureModeCustom`) 以及镜头对位 (`setFocusModeLocked`) 。
- **实时图像处理管线**: 需熟练处理视频帧流由 `CMSampleBuffer` -> `CVPixelBuffer` -> `CIImage` 的转化，配合各种核心 CIFilter (调整曝光、调整高光和阴影) 优化夜拍画面。
- **并发与多线程设计**: Camera 的硬件处理高度利用串行调度队列 (如 `sessionQueue`, `videoOutputQueue`) ，这避免了耗时的相机会话配置以及高频每秒30/60次视频帧处理发生阻塞。同时，最终展现层操作强制在 `DispatchQueue.main` 队列中完成。

## 核心限制条件 (Important Constraints)
- **预览的高性能管理**: 由于夜空中包含大量噪点和需提亮的画面，管线需要自动舍弃掉迟到的视频帧 (`alwaysDiscardsLateVideoFrames = true`) 来保证可用内存，不引起 OOM 与画面流畅。
- **苹果硬件碎片化兼容**: 非所有设备带有长焦距 (Telephoto) 镜头。需做优雅适配机制（检测优先级：Telephoto镜头 -> 双广角 -> 广角，并配合修改 `videoZoomFactor` 实施默认数码变焦）。
- **用户级权限管理**: 应用中必须包含必要的隐私权限解释 (`NSCameraUsageDescription` 权限捕获、`NSPhotoLibraryAddUsageDescription` 权限写入图像），并在代码层面执行对应的权限检测再进行存取操作。
