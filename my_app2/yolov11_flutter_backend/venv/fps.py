import cv2

cap = cv2.VideoCapture(0)  # 0 ise varsayılan kamera

fps = cap.get(cv2.CAP_PROP_FPS)
print(f"FPS: {fps}")

cap.release()
