"""Genera el mock estático de EntregaYa para comprobantes de entrega.

Por cada envío Entregado escribe mock/entregaya/proofs/<proofId> con el JSON que documenta el
proveedor (GET {URL base}/proofs/{proofId}): proofId, trackingNumber, signedBy, fileName, pdfBase64.

Uso:
  sf data query -q "SELECT Name, Proof_Id__c, Recipient_Name__c, Recipient_Address__c FROM Shipment__c \
      WHERE Proof_Id__c != null ORDER BY Name" --result-format csv > delivered.csv
  python3 scripts/mock/generate-entregaya-proofs.py delivered.csv

Los datos son ficticios (los del seed). Se sirve por jsDelivr, que ignora el header Authorization.
"""
import base64
import csv
import io
import json
import math
import os
import sys

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'mock', 'entregaya', 'proofs')
BRAND = HexColor('#0b6b5d')


def signature(c, x, y, name, seed):
    """Firma manuscrita simulada: una curva determinista por persona."""
    c.setStrokeColor(HexColor('#1d3a8a'))
    c.setLineWidth(1.6)
    p = c.beginPath()
    p.moveTo(x, y)
    for i in range(1, 160):
        t = i / 159
        px = x + t * 190
        py = y + 14 * math.sin(t * (9 + seed % 5) + seed) * (1 - t * 0.6) + 6 * math.sin(t * 31 + seed)
        p.lineTo(px, py)
    c.drawPath(p)
    c.line(x + 20, y - 12, x + 170, y - 6)


def pdf(row, seed):
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=letter)
    c.setTitle(f"Comprobante de entrega {row['Name']}")
    c.setAuthor('EntregaYa (ambiente de pruebas)')
    w, h = letter
    c.setFillColor(BRAND)
    c.rect(0, h - 90, w, 90, fill=1, stroke=0)
    c.setFillColor(HexColor('#ffffff'))
    c.setFont('Helvetica-Bold', 22)
    c.drawString(50, h - 55, 'EntregaYa')
    c.setFont('Helvetica', 11)
    c.drawString(50, h - 75, 'Comprobante de entrega · ambiente de pruebas (datos ficticios)')

    c.setFillColor(HexColor('#1d2433'))
    rows = [
        ('Número de guía', row['Name']),
        ('Comprobante', row['Proof_Id__c']),
        ('Recibió', row['Recipient_Name__c']),
        ('Dirección de entrega', row['Recipient_Address__c']),
        ('Transportista', 'EntregaYa · última milla para RutaCargo'),
    ]
    y = h - 140
    for label, value in rows:
        c.setFont('Helvetica', 9)
        c.setFillColor(HexColor('#5b6475'))
        c.drawString(50, y, label.upper())
        c.setFont('Helvetica-Bold', 13)
        c.setFillColor(HexColor('#1d2433'))
        c.drawString(50, y - 17, value)
        y -= 48

    c.setFont('Helvetica', 9)
    c.setFillColor(HexColor('#5b6475'))
    c.drawString(50, y - 10, 'FIRMA DE QUIEN RECIBIÓ')
    signature(c, 60, y - 60, row['Recipient_Name__c'], seed)
    c.setStrokeColor(HexColor('#dde2ea'))
    c.line(50, y - 85, 300, y - 85)
    c.setFont('Helvetica', 10)
    c.setFillColor(HexColor('#1d2433'))
    c.drawString(50, y - 100, row['Recipient_Name__c'])

    c.setFont('Helvetica-Oblique', 8)
    c.setFillColor(HexColor('#8a93a3'))
    c.drawString(50, 40, 'Documento generado por el mock de EntregaYa para pruebas. No tiene validez.')
    c.showPage()
    c.save()
    return buf.getvalue()


def main(path):
    os.makedirs(OUT, exist_ok=True)
    n = 0
    with open(path, newline='', encoding='utf-8') as f:
        for i, row in enumerate(csv.DictReader(f)):
            body = {
                'proofId': row['Proof_Id__c'],
                'trackingNumber': row['Name'],
                'signedBy': row['Recipient_Name__c'],
                'fileName': f"comprobante-{row['Name']}.pdf",
                'pdfBase64': base64.b64encode(pdf(row, i + 7)).decode('ascii'),
            }
            with open(os.path.join(OUT, row['Proof_Id__c']), 'w', encoding='utf-8') as out:
                json.dump(body, out, ensure_ascii=False)
            n += 1
    print(f'{n} comprobantes en {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main(sys.argv[1])
