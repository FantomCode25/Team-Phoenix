# !pip install pandas numpy scikit-learn joblib

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error
import joblib

np.random.seed(42)  
data = []

for _ in range(100):
    violet = np.random.uniform(443, 505)
    blue = np.random.uniform(1015, 1165)
    ir = np.random.uniform(0, 13724)  
    red = np.random.uniform(0, 13442) 
    signal = "Good" if ir > 5000 else "Weak"
    hb = 0 if signal == "Weak" else 12 + ((ir / 1000 + red / 1000 - violet / 100 - blue / 100) * 0.5 + np.random.uniform(-0.5, 0.5))
    if hb < 12 and signal == "Good": hb = 12  
    if hb > 18 and signal == "Good": hb = 18  
    data.append([violet, blue, ir, red, signal, round(hb, 1)])

df = pd.DataFrame(data, columns=['Violet', 'Blue', 'IR', 'Red', 'Signal', 'Hb'])


df.to_csv('hemoglobin_dataset_100.csv', index=False)
print("Dataset created and saved as 'hemoglobin_dataset_100.csv'")
print(df.head(10)) 

data = pd.read_csv('hemoglobin_dataset_100.csv')


X = data[['Violet', 'Blue', 'IR', 'Red', 'Signal']]  
X['Signal'] = X['Signal'].map({'Good': 1, 'Weak': 0})  
y = data['Hb']  

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
print("Data prepared. Train size:", X_train.shape, "Test size:", X_test.shape)

rf_model = RandomForestRegressor(n_estimators=100, random_state=42)
rf_model.fit(X_train, y_train)

y_pred = rf_model.predict(X_test)

mse = mean_squared_error(y_test, y_pred)
print(f'Mean Squared Error: {mse:.4f}')

importances = rf_model.feature_importances_
feature_names = X.columns
for name, importance in zip(feature_names, importances):
    print(f'Feature: {name}, Importance: {importance:.4f}')

joblib.dump(rf_model, 'rf_hemoglobin_model.pkl')
print("Model saved as 'rf_hemoglobin_model.pkl'")

from google.colab import files
files.download('hemoglobin_dataset_100.csv')
files.download('rf_hemoglobin_model.pkl')
import tensorflow as tf

rf_model_loaded = joblib.load('rf_hemoglobin_model.pkl')

def rf_to_tf_model(rf_model, feature_count):
    model = tf.keras.Sequential([
        tf.keras.layers.Dense(100, input_dim=feature_count, activation='relu'),
        tf.keras.layers.Dense(50, activation='relu'),
        tf.keras.layers.Dense(1)  # Output Hb
    ])
    # Train with dummy data to mimic RF (simplified)
    X_train_array = X_train.values
    model.compile(optimizer='adam', loss='mse')
    model.fit(X_train_array, y_train, epochs=50, verbose=0)
    return model

# Convert
tf_model = rf_to_tf_model(rf_model, X_train.shape[1])
converter = tf.lite.TFLiteConverter.from_keras_model(tf_model)
tflite_model = converter.convert()

# Save TFLite model
with open('rf_hemoglobin_model.tflite', 'wb') as f:
    f.write(tflite_model)
print("TFLite model saved as 'rf_hemoglobin_model.tflite'")
files.download('rf_hemoglobin_model.tflite')