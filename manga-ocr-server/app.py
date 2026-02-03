from fastapi import FastAPI, File, UploadFile
from manga_ocr import MangaOcr
from PIL import Image
import io

app = FastAPI()
mocr = MangaOcr()

@app.post("/ocr")
async def recognize_text(image: UploadFile = File(...)):
    contents = await image.read()
    img = Image.open(io.BytesIO(contents))
    text = mocr(img)
    return {"text": text}

@app.post("/ocr/batch")
async def recognize_batch(images: list[UploadFile] = File(...)):
    results = []
    for image in images:
        contents = await image.read()
        img = Image.open(io.BytesIO(contents))
        text = mocr(img)
        results.append({"text": text})
    return {"results": results}
