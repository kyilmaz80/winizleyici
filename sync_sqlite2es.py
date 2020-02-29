# -*- coding: utf-8 -*-

import sqlite3
from sqlite3 import Error
import json
from elasticsearch import Elasticsearch
from elasticsearch.helpers import bulk, streaming_bulk
from collections import OrderedDict
import uuid
import logging
import os

"""
SQlite veri tabanindaki gorunum tablosundaki
veriyi okur ve ElasticSearch'e gonderir.
"""

__author__ = "Koray YILMAZ, Can KAYA"
__copyright__ = "Copyright 2020, WinIzleyici Projesi - Veri Aktarim"
__version__ = "1.0.1"


#sqlite parameters
SQLITEDB_PATH = "worklog.db"
SQLITE_VIEW_NAME = "vw_workdata"
MAX_RECORD_LEN = 10
#elasticsearch parameters
HOST = "elasticsearch.aryasoft.com.tr"
USERNAME = "elasticsearch"
PASSWORD = "SecureElast1c"
PORT = "8080"
INDEX_NAME = "test-ky"
DOCUMENT_TYPE = "_doc"

"""sqllite viewden aldığımuz kolonları dictionary objesine
çevrilirken verilen key degerleri"""

ES_KEYS = [
    "worklogId",
    "processName",
    "windowTitle",
    "userName",
    "startDate",
    "endDate",
    "durationasMin"
]

ES_MAPPINGS =  {
    "mappings": {
        "properties": {
            "worklogId": {
                "type": "integer"
            },
            "processName": {
                "type": "text"
            },
            "windowTitle": {
                "type": "text"
            },
            "userName": {
                "type": "text"
            },
            "startDate": {
                "type": "text",
                "format": "yyyy-MM-dd HH:mm:ss"
            },
            "endDate": {
                "type": "text",
                "format": "yyyy-MM-dd HH:mm:ss"
            },
            "durationasMin": {
                "type": "integer"
            }
        }
    }
}

VIEW_STATEMENT = """
CREATE VIEW """+SQLITE_VIEW_NAME+""" 
AS 
SELECT
    w.id as worklogId,
    p.name as processName, 
    wi.title as windowTitle, 
    u.name as userName, 
    w.start_date as startDate, 
    w.end_date as endDate, 
    (julianday(w.end_date)- julianday(w.start_date))*24*60 as durationasMin 
FROM  
    Worklog w 
    INNER JOIN Process p ON w.p_id=p.id 
    INNER JOIN Window wi ON w.w_id=wi.id 
    INNER JOIN User u ON w.u_id=u.id 
WHERE 
    w.processed=0 
ORDER BY 
    w.id asc
"""

UPDATE_STATEMENT = "UPDATE main.Worklog Set processed = 1 WHERE main.Worklog.id = ?"


"""
SQlite veri tabanina baglanti doner
"""
def create_connection(db_file):
    """ create a database connection to the SQLite database
    specified by the db_file
    :param db_file: database file
    :return: Connection object or None
    """
    conn = None
    logger = logging.getLogger("db")
    logger.info("sqlite veri tabani aciliyor..")
    if not os.path.isfile(db_file):
        logger.error("sqlite veri tabani dosyasi: %s bulunamadi..", db_file)
        return None
    try:
        conn = sqlite3.connect(db_file)
    except Error as e:
        logger.error(e)
 
    return conn


"""
Sqlite view siler
"""
def dropView(conn):
    cur = conn.execute("DROP VIEW ?", (SQLLITE_VIEW_NAME,))
    conn.commit()
    return cur

"""
Sqlite view olusturur
"""
def createView(conn):
    cur = conn.execute(VIEW_STATEMENT)
    conn.commit()
    return cur

"""
Sqlite view'dan record_limit kadar veri sorgular ve doner
"""
def select_sqlitedata(conn, record_limit):
    logger = logging.getLogger(__name__)

    SELECT_SQL = """SELECT worklogId, processName, windowTitle, userName,
                    startDate, endDate, durationasMin
                    FROM """ +  SQLITE_VIEW_NAME + """ LIMIT ?"""
    
    cur = conn.cursor()
    row = []
    try:
        cur.execute(SELECT_SQL, (record_limit,))
    except Error as e:
        logger.error(e)
        if "no such table" in str(e):
            logging.warning("%s view tablosu olusturuluyor...", SQLITE_VIEW_NAME)
            createView(conn)
            cur.execute(SELECT_SQL, (record_limit,))

    rows = cur.fetchall()
    return rows

"""
elasticsearch bulk ile gonderilen worklog id'leri icin SQlite db'de
Worklog tablosundaki processed kolonunu 1 olarak gunceller.
"""
def update_sqlitedata_worklog(conn, wid_list):
    logger = logging.getLogger("db")

    updated = False
    cur = conn.cursor()

    try:
        for wid in wid_list:
            cur.execute(UPDATE_STATEMENT, (wid,))
        conn.commit()
        updated = True
    except Error as e:
        logger.error(e)
    return updated


"""
Sqlite icin data_dict_list veri yapisini tupple a cevirir
"""
def get_worklog_ids_tuple(data_dict_list):
    worklog_ids = []
    for data_dict in data_dict_list:
        worklog_ids.append(data_dict['worklogId'])
    return tuple(worklog_ids)


"""
elasticsearch sunucuya baglanti doner
"""
def connect_to_elastic(host, port, username, password):
    es = Elasticsearch(host=host, port=port,
                       http_auth=(username, password),)
    if es.ping():
        return es
    else:
        return None


"""
elasticsearch index i mapping i ile olusturur
"""
def create_elastic_index(es, index_name):
    logger = logging.getLogger(__name__)
    created = False
    mapping = ES_MAPPINGS
    try:
        es.indices.create(index=index_name, ignore=400, body=mapping)
        logger.info("%s indeksi ilk defa olusturuluyor...", index_name)
        created = True
    except  Exception as e:
        logger.error("Index Create Hata!")
        logger.error(e)
    finally:
        return created


"""
elasticsearch index i siler
"""
def delete_elastic_index(es, index_name):
    logger = logging.getLogger(__name__)
    logger.info("%s indeksi siliniyor...", index_name)
    res = es.indices.delete(index_name)
    return res["acknowledged"]


"""
elasticsearch e veri ekler
"""
def insert_to_elasticsearch(es, index_name, data_json, doc_type):
    logger = logging.getLogger(__name__)
    res = {}
    res["result"] = ""
    if es.ping():
        try:
            #TODO: mapper hatası mapper_parsing_exception
            res = es.index(index_name, body=data_json,
                           doc_type=doc_type)
        except Exception as e:
            logger.error(e)
        return res["result"] == "created"
    else:
        return None


"""
data_dict_list olarak gelen veriden
json formatinda ES bulk icin iterator doner
"""
def gen_data(data_rows):
    for data in data_rows:
        yield {
            "id": str(uuid.uuid4()),
            "_index": INDEX_NAME,
            "_type": "_doc",
            "_source": data,
        }


"""
Sqlite3 cursor select sonucunu python dict_list
veri yapisina donusturur
"""
def record_to_dict_list(rows_list):
    data_rows = []
    logger = logging.getLogger(__name__)
    if len(rows_list) == 0:
        logger.error("AssertionError: rows_list boyutu 0 geldi!")
    assert len(rows_list) != 0

    # rows bir liste
    # icinde de tupple var
    keys = ES_KEYS

    for row_tupple in rows_list:
        #print("row_tupple: ", row_tupple)
        data_dict = {}
        for i in range(len(row_tupple)):
            data_dict[keys[i]] = row_tupple[i]
        data_rows.append(data_dict)
    # son data normalize olabildiginden silinmeli listeden
    if len(rows_list) > 1:
        data_rows.pop() # last row siliniyor...
    return data_rows


def main():

    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(filename='sync.log', format=log_format,
                        level=logging.DEBUG)
    
    logger = logging.getLogger(__name__)

    # create a database connection or die
    conn = create_connection(SQLITEDB_PATH)
    if conn == None:
        logger.error("Program Exit")
        return

    data = {}

    logger.info("SQLite veri tabani sorgulaniyor...")
    with conn:
        data = select_sqlitedata(conn, MAX_RECORD_LEN)

    if len(data) == 0:
        logger.info("view'da proses edilmemis veriye rastlanmadi")
        return
    elif len(data) == 1:
        logger.info("normalize veri eklenmiyor...")
        return
    
    #elasticsearch  connect & insert
    data_dict_list = record_to_dict_list(data)
    es  = connect_to_elastic(HOST, PORT, USERNAME, PASSWORD)
    if es == None:
        logger.error("Elasticsearch sunucu baglantisi alinamadi!")
        return
    
    res_bulk = None
    err_bulk = False
    
    if es:
        # index yoksa olusturur
        if not es.indices.exists(INDEX_NAME):
            create_elastic_index(es, INDEX_NAME)
        # es ye kayitlari ekle
        try:
            res_bulk = bulk(es, gen_data(data_dict_list))
            if len(data_dict_list) != res_bulk[0]:
                logger.error("Bulk Insert eklenen ile gonderilen farkli!")
                err_bulk = True
        except Exception as e:
            err_bulk = True
            logger.error(e)

        if res_bulk is None or err_bulk:
            logger.error("bulk Insert hatasi! Data: %s", data_dict_list)

        if not err_bulk:
            logger.info("bulk basarili")
            logging.info("Worklow tablosunda process edilen idler update ediliyor...")
            with conn:
                wids_tuple = get_worklog_ids_tuple(data_dict_list)
                logging.info("Update edilecek worklog_idler: %s", wids_tuple)
                res = update_sqlitedata_worklog(conn, wids_tuple)
                if res:
                    logger.info("Worklog update basarili")
                else:
                    logger.info("Worklog update basarili degil!")
    else:
        logger.error("Insert edilemedi!")
    
 
if __name__ == '__main__':
    main()
