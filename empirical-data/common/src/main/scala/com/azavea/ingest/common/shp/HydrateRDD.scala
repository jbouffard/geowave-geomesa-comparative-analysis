package com.azavea.ingest.common.shp

import org.apache.spark._
import org.apache.spark.rdd.RDD
import org.geotools.data.DataStoreFinder
import org.geotools.data.simple.SimpleFeatureStore
import org.opengis.feature.simple._
import org.geotools.feature.simple._
import org.geotools.feature._
import com.amazonaws.auth._
import com.amazonaws.services.s3.AmazonS3Client
import com.amazonaws.services.s3.model.ListObjectsRequest

import java.util.HashMap
import scala.collection.JavaConversions._
import scala.collection.mutable

import com.azavea.ingest.common._

object HydrateRDD extends HydrateRDDUtils {
  def getShpUrls(s3bucket: String, s3prefix: String): Array[String] = {
    val objectRequest = (new ListObjectsRequest)
      .withBucketName(s3bucket)
      .withPrefix(s3prefix)

    listKeys(objectRequest)
      .collect({ case key if key.endsWith(".shp") =>
        s"https://s3.amazonaws.com/${s3bucket}/${key}"
      }).toArray
  }

  def shpUrlsToRdd(urlArray: Array[String])(implicit sc: SparkContext): RDD[SimpleFeature] = {
    val urlRdd: RDD[String] = sc.parallelize(urlArray, urlArray.size / 10)
    urlRdd.mapPartitions({ urlIter =>
      val urls = urlIter.toList
      urls.map({ url =>
        val datastoreParams = Map("url" -> url)
        val shpDS = DataStoreFinder.getDataStore(datastoreParams)
        if (shpDS == null) {
          println("Could not build ShapefileDataStore")
          java.lang.System.exit(-1)
        }
        val featureCollection = shpDS.getFeatureSource(shpDS.getNames()(0)).getFeatures
        featureCollection.toArray.asInstanceOf[Array[SimpleFeature]]
      }).flatten.iterator
    })
  }

}
