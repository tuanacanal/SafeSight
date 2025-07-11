import onnx
import tensorflow as tf
from onnx_tf.backend import prepare

# ONNX modelini yükleyin
onnx_model = onnx.load('/Users/tuana/Desktop/my_app2/best.onnx')

# ONNX modelini TensorFlow formatına dönüştürün
tf_rep = prepare(onnx_model)

# TensorFlow modelini kaydedin
tf_rep.export_graph('converted_model')

# TensorFlow modelini yükleyin
model = tf.saved_model.load('converted_model')

# Model hakkında bilgi alın
print(model)

