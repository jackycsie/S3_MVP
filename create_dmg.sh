#!/bin/bash

# 設置變數
APP_NAME="S3_MVP"
VERSION="0.1.0"
DMG_NAME="${APP_NAME}_${VERSION}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"
SOURCE_APP="/Users/sphuang/Desktop/S3_MVP_2025-04-01_18-05-22/S3_MVP.app"  # 這裡需要替換為實際的 .app 路徑
DMG_PATH="./build/${DMG_NAME}"
TMP_DMG_PATH="./build/${APP_NAME}_tmp.dmg"
BACKGROUND_FILE="./build/background.png"  # 如果你想添加背景圖片

# 創建必要的目錄
mkdir -p ./build

# 檢查源文件是否存在
if [ ! -d "${SOURCE_APP}" ]; then
    echo "Error: ${SOURCE_APP} not found!"
    exit 1
fi

# 創建臨時 DMG
hdiutil create -size 100m -volname "${VOLUME_NAME}" -srcfolder "${SOURCE_APP}" -ov -format UDRW "${TMP_DMG_PATH}"

# 掛載 DMG
MOUNT_POINT="/Volumes/${VOLUME_NAME}"
hdiutil attach "${TMP_DMG_PATH}"

# 等待掛載完成
sleep 2

# 創建 Applications 的符號連結
ln -s /Applications "${MOUNT_POINT}/Applications"

# 設置視窗大小和圖標位置
echo '
   tell application "Finder"
     tell disk "'${VOLUME_NAME}'"
           open
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           set the bounds of container window to {400, 100, 900, 400}
           set theViewOptions to the icon view options of container window
           set arrangement of theViewOptions to not arranged
           set icon size of theViewOptions to 72
           set position of item "'${APP_NAME}'.app" of container window to {150, 150}
           set position of item "Applications" of container window to {350, 150}
           close
           open
           update without registering applications
           delay 5
           close
     end tell
   end tell
' | osascript

# 等待 Finder 完成
sleep 5

# 卸載 DMG
hdiutil detach "${MOUNT_POINT}"

# 轉換 DMG 為壓縮格式
hdiutil convert "${TMP_DMG_PATH}" -format UDZO -o "${DMG_PATH}"

# 清理臨時文件
rm "${TMP_DMG_PATH}"

echo "DMG created at ${DMG_PATH}" 
