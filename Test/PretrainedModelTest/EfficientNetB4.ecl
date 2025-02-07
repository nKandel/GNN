/*##############################################################################
## HPCC SYSTEMS software Copyright (C) 2023 HPCC Systems.  All rights reserved.
############################################################################## */
/*
About this test:
  Test the usability of Pre-trained Model EfficientNetB4.
  Reference: https://www.tensorflow.org/api_docs/python/tf/keras/applications/efficientnet/EfficientNetB4
  Input shape = (380, 380, 3) 

Results:

class                   probability
tusker	                0.7335491180419922
African_elephant	      0.1147932857275009
Indian_elephant	        0.002987296786159277
*/

IMPORT Python3 AS Python;
IMPORT $.^ AS GNN;
IMPORT GNN.GNNI;
IMPORT GNN.Tensor;
IMPORT GNN.Internal AS int;
IMPORT GNN.Internal.Types AS iTypes;
IMPORT Std.System.Thorlib;
IMPORT STD;

kString := iTypes.kString;
kStrType := iTypes.kStrType;
t_Tensor := Tensor.R4.t_Tensor;
TensData := Tensor.R4.TensData;

// load the test data, an image of an elephant
imageRecord := RECORD
  STRING filename;
  DATA   image;   
       //first 4 bytes contain the length of the image data
  UNSIGNED8  RecPos{virtual(fileposition)};
END;

imageData := DATASET('~le::elephant',imageRecord,FLAT);

result := (STRING)(imageData[1].image);

SET OF INTEGER hexToNparry(DATA byte_array):= EMBED(Python)
  from PIL import Image
  import numpy as np
  import io
  try:
    import tensorflow as tf # V2.x
  except:
    assert 1 == 0, 'tensorflow not found'
  bytes_data = bytes(byte_array)
  image = Image.open(io.BytesIO(bytes_data))
  image = image.resize((380,380))
  I_array = np.array(image)
  I_array = tf.keras.applications.efficientnet.preprocess_input(I_array)
  return I_array.flatten().tolist()
ENDEMBED;

valueRec := RECORD
  INTEGER value;
END;

idValueRec := RECORD
  UNSIGNED8 id;
  INTEGER value;
END;

imageNpArray := hexToNparry(imageData[1].image);
x1 := DATASET(imageNpArray, valueRec);
x2 := PROJECT(x1, TRANSFORM(idValueRec, SELF.id := COUNTER - 1, SELF.value := LEFT.value));
x3 := PROJECT(x2, TRANSFORM(TensData, SELF.indexes := [1, TRUNCATE(LEFT.id/(380*3)) + 1, TRUNCATE(LEFT.id/3)%380 + 1, LEFT.id%3 + 1], SELF.value := LEFT.value));
x := Tensor.R4.MakeTensor([0,380,380,3], x3);

// load the model
s := GNNI.GetSession(1);
ldef := ['''applications.efficientnet.EfficientNetB4(weights = "imagenet")'''];
mod := GNNI.DefineModel(s, ldef);

// Predict 
preds_tens := GNNI.Predict(mod, x);
preds := Tensor.R4.GetData(preds_tens);

OUTPUT(preds, NAMED('preds'));

predictRes := RECORD
  STRING class;
  REAL4 probability;
END;

// decode predictions
DATASET(predictRes) decodePredictions(DATASET(TensData) preds, INTEGER topK = 3) := EMBED(Python)
  try:
    from tensorflow.keras.applications.efficientnet import decode_predictions
  except:
    assert 1 == 0, 'tensorflow not found'
  import numpy as np
  predsNp = np.zeros((1, 1000))
  for pred in preds:
    predsNp[0, pred[0][1]-1] = pred[1]
  res = decode_predictions(predsNp, top=topK)[0]
  ret = []
  for i in range(topK):
    ret.append((res[i][1], res[i][2]))
  return ret
ENDEMBED;

OUTPUT(decodePredictions(preds), NAMED('predictions'));
