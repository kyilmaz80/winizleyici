import sqlite3
from sqlite3 import Error
import json
from elasticsearch import Elasticsearch
from elasticsearch.helpers import bulk, streaming_bulk
from collections import OrderedDict
import uuid

# region PRE_DEFINED_STATIC_VARIABLES
DATABASE_PATH = r"worklog.db"
# sqlite parameters
MAX_RECORD_LEN = 10
SQLLITE_VIEW_NAME = "vw_workdata"
# elasticsearch parameters
HOST = "elasticsearch.aryasoft.com.tr"
USERNAME = "elasticsearch"
PASSWORD = "SecureElast1c"
PORT = "8080"
INDEX_NAME = "test"
DOCUMENT_TYPE = "_doc"


"""sqllite viewden aldığımuz kolonları dictionary objesine
çevrilirken verilen key degerleri"""

keys =[
    "processname",
    "windowtitle",
    "username",
    "createdate",
    "enddate",
    "durationmin"
]

request_body = {
    "settings": {
        "number_of_shards": 5,
        "number_of_replicas": 1
    },
    'mappings': {
        "properties": {
            "processname": {"type": "text"},
            "windowtitle": {"type": "text"},
            "username": {"type": "text"},
            "createdate": {"type": "date", "format": "yyyy-MM-dd HH:mm:ss"},
            "enddate": {"type": "date", "format": "yyyy-MM-dd HH:mm:ss"},
            "durationmin": {"type": "double"}
        }
    }
}

VIEW_STATEMENT = """
CREATE VIEW """+SQLLITE_VIEW_NAME+""" 
AS 
SELECT  
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

# endregion


# region sqlLiteFunctions

def dropView(conn):
    cur = conn.execute("DROP VIEW ?", (SQLLITE_VIEW_NAME,))
    return cur


def createView(conn):
    cur = conn.execute(VIEW_STATEMENT)
    return cur


def create_connection(db_file):
    """ verilen sqllite veri tabani dosyasina baglanir
    :return: Connection object or None
    """
    conn = None
    try:
        conn = sqlite3.connect(db_file)
    except Error as e:
        print(e)
    return conn


def select_all_rows(conn):
    """ baglantidaki tüm veriyi getirir.
    :return: 
    """
    cur = conn.cursor()
    cur.execute("SELECT * FROM ? ", (SQLLITE_VIEW_NAME,))

    rows = cur.fetchall()
    return rows


def select_sqlitedata(conn, limitCount):
    """
    verilen baglantidaki limit sayisina 
    bagli olarak verileri getirir
    :return:
    """
    cur = conn.cursor()
    cur.execute("SELECT * FROM "+SQLLITE_VIEW_NAME+" LIMIT ?", ( limitCount,))

    rows = cur.fetchall()
    return rows

# endregion


# region elasticSearchFunctions

def createElasticIndex(es):
    res = es.indices.create(index=INDEX_NAME)
    return res["acknowledged"]


def createElasticIndexwithMapping(es):
    res = es.indices.create(index=INDEX_NAME, body=request_body)
    return res["acknowledged"]


def deleteElasticIndex(es):
    res = es.indices.delete(index=INDEX_NAME)
    return res["acknowledged"]


def checkIndexExists(es):
    if not es.indices.get(index=INDEX_NAME):
        createElasticIndexwithMapping(es)


def connect_to_elastic(host, port, username, password):
    es = Elasticsearch(host=host, port=port, http_auth=(username, password),)
    if es.ping():
        return es
    else:
        return None


def insert_to_elasticsearch(es, index_name, data_json, doc_type):
    #es  = connect_to_elastic(host, port, username, password)
    res = {}
    res["result"] = ""
    if es.ping():
        try:
            # TODO: mapper hatası mapper_parsing_exception
            print(data_json)
            res = es.index(index_name, body=data_json,
                           doc_type=doc_type)
        except Exception as e:
            print(e)
        return res["result"] == "created"
    else:
        return None


# endregion


# region Helpers

def rows_to_dict(rows_list):
    data_rows = []
    assert len(rows_list) != 0
    # rows bir liste
    # icinde de tupple var
    for row_tupple in rows_list:
        #print("row_tupple: ", row_tupple)
        data_dict = {}
        for i in range(len(row_tupple)):
            data_dict[keys[i]] = row_tupple[i]
        data_rows.append(data_dict)
    if len(rows_list) > 1:
        data_rows.pop()  # last row siliniyor...

    return data_rows


def gen_data(data_rows):
    for data in data_rows:
        yield {
            "id": str(uuid.uuid4()),
            "_index": INDEX_NAME,
            "_type": DOCUMENT_TYPE,
            "_source": data,
        }

# endregion


def main():

    # create a database connection
    conn = create_connection(DATABASE_PATH)
    data = {}

    # get data from sqllite
    with conn:
        data = select_sqlitedata(conn, MAX_RECORD_LEN)

    # elasticsearch  connect & insert
    es = connect_to_elastic(HOST, PORT, USERNAME, PASSWORD)

    if es:
        try:
            res = bulk(es, gen_data(rows_to_dict(data)))
        except Exception as e:
            print(e)

        print("result = ", res)
    else:
        print("Insert edilemedi!")


if __name__ == '__main__':
    main()
