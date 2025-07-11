from flask import Flask, request, jsonify, Response
from ultralytics import YOLO
import cv2
import tempfile
import os
import base64
import numpy as np
from sort import Sort  # SORT algoritması, nesne takibi için kullanılıyor
from filterpy.kalman import KalmanFilter  # Kalman Filter, isteğe bağlı takip için (şimdilik kullanılmıyor)
# from yolox.tracker.byte_tracker import BYTETracker  # ByteTrack tracker sınıfı


app = Flask(__name__)  # Flask uygulamasını başlatıyoruz

# YOLOv11 modelimizi yüklüyoruz, burada eğitimli ağırlık dosyasının yolu belirtilmiş
model = YOLO("/Users/tuana/Desktop/my_app2/yolov11_flutter_backend/venv/best.pt")

# --- FOTOĞRAF ÜZERİNDEN NESNE TESPİTİ ---
@app.route("/predict", methods=["POST"])
def predict():
    # İstek dosyasında 'image' anahtarı yoksa hata döndür
    if "image" not in request.files:
        return jsonify({"error": "Görsel bulunamadı"}), 400

    # Kullanıcıdan gelen görsel dosyasını oku
    image_file = request.files["image"]
    # Görseli byte dizisine çevirip OpenCV formatına decode et
    image_array = np.frombuffer(image_file.read(), np.uint8)
    img = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

    # Model ile tespit yap
    results = model(img)

    predictions = []
    # Tespit edilen kutuların üzerinden geç
    for box in results[0].boxes:
        x1, y1, x2, y2 = map(int, box.xyxy[0])  # Kutu koordinatları
        label = results[0].names[int(box.cls[0])]  # Tespit edilen nesne sınıfı
        conf = float(box.conf[0])  # Güven skoru

        # Güven skoru %50 ve üzerindeyse sonucu kaydet ve görsele kutu çiz
        if conf >= 0.5:
            predictions.append({
                "label": label,
                "confidence": conf,
                "box": [x1, y1, x2, y2]
            })
            # Görsel üzerine yeşil renkli kutu çiz
            cv2.rectangle(img, (x1, y1), (x2, y2), (0, 255, 0), 2)
            # Nesne adı ve güven skorunu yaz
            cv2.putText(img, f"{label} {conf:.2f}", (x1, y1 - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

    # Görseli tekrar jpg formatına encode et ve base64 stringe dönüştür
    _, buffer = cv2.imencode('.jpg', img)
    image_base64 = base64.b64encode(buffer).decode('utf-8')

    # Tespit sonuçlarını ve işlenmiş görseli JSON olarak döndür
    return jsonify({
        "predictions": predictions,
        "image_base64": image_base64
    })


# --- VİDEO ÜZERİNDEN NESNE TESPİTİ VE TAKİP ---
@app.route("/video_predict", methods=["POST"])
def video_predict():
    # Video dosyası yoksa hata döndür
    if "video" not in request.files:
        return jsonify({"error": "Video bulunamadı"}), 400

    video_file = request.files["video"]
    # Geçici bir dosya oluşturup video dosyasını oraya kaydet
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as temp:
        input_path = temp.name
        video_file.save(input_path)

    # VideoCapture ile videoyu aç
    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        # Video açılamazsa geçici dosyayı sil ve hata döndür
        os.remove(input_path)
        return jsonify({"error": "Video açılamadı"}), 400

    # Videonun fps, genişlik ve yüksekliğini al
    fps = cap.get(cv2.CAP_PROP_FPS) or 25
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    # Eğer video boyutu geçersizse işlemi iptal et
    if width == 0 or height == 0:
        cap.release()
        os.remove(input_path)
        return jsonify({"error": "Geçersiz video boyutu"}), 400

    # Çıktı videosunu kaydetmek için geçici dosya yolu oluştur
    output_path = os.path.join(tempfile.gettempdir(), "output.mp4")
    # Video codec ayarı
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    # VideoWriter ile çıktı videosu aç
    out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))
    if not out.isOpened():
        cap.release()
        os.remove(input_path)
        return jsonify({"error": "Çıktı videosu başlatılamadı"}), 500

    tracker = Sort()  # SORT nesne takip algoritması başlat

    while True:
        ret, frame = cap.read()
        if not ret:  # Video bittiğinde döngüyü kır
            break

        # Frame üzerinde model ile tahmin yap (daha yüksek eşiklerle)
        results = model.predict(frame, conf=0.6, iou=0.5)
        detections = []

        # Her tespit için güven skoru ve koordinatları al
        for box in results[0].boxes:
            conf = float(box.conf[0])
            if conf >= 0.6:
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                detections.append([x1, y1, x2, y2, conf])

        # Numpy dizisine çevir, eğer tespit yoksa boş dizi oluştur
        detections_np = np.array(detections, dtype=float)
        if detections_np.shape[0] == 0:
            detections_np = np.empty((0, 5))

        # SORT algoritması ile nesneleri takip et, ID ata
        tracked_objects = tracker.update(detections_np)

        # Takip edilen nesnelerin kutularını ve ID'lerini frame üzerine çiz
        for *box, track_id in tracked_objects:
            x1, y1, x2, y2 = map(int, box)
            cv2.rectangle(frame, (x1, y1), (x2, y2), (255, 0, 0), 2)  # Mavi kutu
            cv2.putText(frame, f"ID {int(track_id)}", (x1, y1 - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 0), 2)

        # Güncellenen frame'i çıktı videosuna yaz
        out.write(frame)

    # İşlem bitti, kaynakları serbest bırak
    cap.release()
    out.release()
    os.remove(input_path)  # Geçici video dosyasını sil

    # Eğer çıktı videosu oluşmamışsa hata döndür
    if not os.path.exists(output_path):
        return jsonify({"error": "Video işlenemedi"}), 500

    # Çıktı videosunu oku ve byte olarak döndür
    with open(output_path, "rb") as f:
        video_bytes = f.read()

    os.remove(output_path)  # Çıktı videosunu da sil

    # Video içeriğini uygun header ile response olarak gönder
    return video_bytes, 200, {
        "Content-Type": "video/mp4",
        "Content-Disposition": "inline; filename=output.mp4"
    }


# --- CANLI KAMERA ÜZERİNDEN ANLIK NESNE TESPİTİ ---
def generate_frames():
    cap = cv2.VideoCapture(0)  # Kamera aç (varsayılan cihaz)

    if not cap.isOpened():
        print("Kamera açılamadı!")
        return

    while True:
        success, frame = cap.read()
        if not success:
            break  # Kamera görüntüsü alınamazsa çık

        # Her frame üzerinde nesne tespiti yap
        results = model(frame)

        # Tespit edilen kutuları ve etiketleri frame üzerine çiz
        for box in results[0].boxes:
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            label = results[0].names[int(box.cls[0])]
            conf = float(box.conf[0])
            if conf >= 0.5:
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(frame, f"{label} {conf:.2f}", (x1, y1 - 10),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

        # Frame'i JPEG formatına encode et
        _, buffer = cv2.imencode('.jpg', frame)
        frame_bytes = buffer.tobytes()

        # Streaming için frame'i uygun biçimde yield et
        yield (b'--frame\r\n'
               b'Content-Type: image/jpeg\r\n\r\n' + frame_bytes + b'\r\n')

    cap.release()  # Kamera serbest bırakılır

@app.route('/live_predict')
def live_predict():
    # Canlı görüntüyü multipart response olarak stream et
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

# Uygulamayı başlat
if __name__ == "__main__":
    # Tüm ağdan erişilebilir şekilde 5001 portunda çalıştır
    app.run(host="0.0.0.0", port=5001)
