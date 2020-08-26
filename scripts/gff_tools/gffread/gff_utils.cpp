#include "gff_utils.h"

bool verbose=false; //same with GffReader::showWarnings and GffLoader::beVserbose

//bool debugState=false;
/*
void printTabFormat(FILE* f, GffObj* t) {
	static char dbuf[1024];
	fprintf(f, "%s\t%s\t%c\t%d\t%d\t%d\t", t->getID(), t->getGSeqName(), t->strand, t->start, t->end, t->exons.Count());
	t->printExonList(f);
	if (t->hasCDS()) fprintf(f, "\t%d:%d", t->CDstart, t->CDend);
	 else fprintf(f, "\t.");

	if (t->getGeneID()!=NULL)
	    fprintf(f, "\tgeneID=%s",t->getGeneID());
	if (t->getGeneName()!=NULL) {
	    GffObj::decodeHexChars(dbuf, t->getGeneName());
	    fprintf(f, "\tgene_name=%s", dbuf);
	}
	if (t->attrs!=NULL) {
	    for (int i=0;i<t->attrs->Count();i++) {
	       const char* attrname=t->getAttrName(i);
	       GffObj::decodeHexChars(dbuf, t->attrs->Get(i)->attr_val);
	       fprintf(f,"\t%s=%s", attrname, dbuf);
	    }
	}
	fprintf(f, "\n");
}
*/

void printFasta(FILE* f, GStr& defline, char* seq, int seqlen, bool useStar) {
 if (seq==NULL) return;
 int len=(seqlen>0)?seqlen:strlen(seq);
 if (len<=0) return;
 if (!defline.is_empty())
     fprintf(f, ">%s\n",defline.chars());
 int ilen=0;
 for (int i=0; i < len; i++, ilen++) {
   if (ilen == 70) {
     fputc('\n', f);
     ilen = 0;
     }
   if (useStar && seq[i]=='.')
        putc('*', f);
   else putc(seq[i], f);
   } //for
 fputc('\n', f);
}

int qsearch_gloci(uint x, GList<GffLocus>& loci) {
  //binary search
  //do the simplest tests first:
  if (loci[0]->start>x) return 0;
  if (loci.Last()->start<x) return -1;
  uint istart=0;
  int i=0;
  int idx=-1;
  int maxh=loci.Count()-1;
  int l=0;
  int h = maxh;
  while (l <= h) {
     i = (l+h)>>1;
     istart=loci[i]->start;
     if (istart < x)  l = i + 1;
          else {
             if (istart == x) { //found matching coordinate here
                  idx=i;
                  while (idx<=maxh && loci[idx]->start==x) {
                     idx++;
                     }
                  return (idx>maxh) ? -1 : idx;
                  }
             h = i - 1;
             }
     } //while
 idx = l;
 while (idx<=maxh && loci[idx]->start<=x) {
    idx++;
    }
 return (idx>maxh) ? -1 : idx;
}

int qsearch_rnas(uint x, GList<GffObj>& rnas) {
  //binary search
  //do the simplest tests first:
  if (rnas[0]->start>x) return 0;
  if (rnas.Last()->start<x) return -1;
  uint istart=0;
  int i=0;
  int idx=-1;
  int maxh=rnas.Count()-1;
  int l=0;
  int h = maxh;
  while (l <= h) {
     i = (l+h)>>1;
     istart=rnas[i]->start;
     if (istart < x)  l = i + 1;
          else {
             if (istart == x) { //found matching coordinate here
                  idx=i;
                  while (idx<=maxh && rnas[idx]->start==x) {
                     idx++;
                     }
                  return (idx>maxh) ? -1 : idx;
                  }
             h = i - 1;
             }
     } //while
 idx = l;
 while (idx<=maxh && rnas[idx]->start<=x) {
    idx++;
    }
 return (idx>maxh) ? -1 : idx;
}

int cmpRedundant(GffObj& a, GffObj& b) {
  if (a.exons.Count()==b.exons.Count()) {
     if (a.covlen==b.covlen) {
       return strcmp(a.getID(), b.getID());
       }
     else return (a.covlen>b.covlen)? 1 : -1;
     }
   else return (a.exons.Count()>b.exons.Count())? 1: -1;
}


bool tMatch(GffObj& a, GffObj& b) {
  //strict intron chain match, or single-exon perfect match
  int imax=a.exons.Count()-1;
  int jmax=b.exons.Count()-1;
  int ovlen=0;
  if (imax!=jmax) return false; //different number of introns

  if (imax==0) { //single-exon mRNAs
    //if (equnspl) {
      //fuzz match for single-exon transfrags:
      // it's a match if they overlap at least 80% of max len
      ovlen=a.exons[0]->overlapLen(b.exons[0]);
      int maxlen=GMAX(a.covlen,b.covlen);
      return (ovlen>=maxlen*0.8);
    /*}
    else {
      //only exact match
      ovlen=a.covlen;
      return (a.exons[0]->start==b.exons[0]->start &&
          a.exons[0]->end==b.exons[0]->end);

       }*/
     }
  //check intron overlaps
  ovlen=a.exons[0]->end-(GMAX(a.start,b.start))+1;
  ovlen+=(GMIN(a.end,b.end))-a.exons.Last()->start;
  for (int i=1;i<=imax;i++) {
    if (i<imax) ovlen+=a.exons[i]->len();
    if ((a.exons[i-1]->end!=b.exons[i-1]->end) ||
      (a.exons[i]->start!=b.exons[i]->start)) {
            return false; //intron mismatch
    }
  }
  return true;
}


bool GffLoader::unsplContained(GffObj& ti, GffObj&  tj) {
 //returns true only if ti (which MUST be single-exon) is "almost" contained in any of tj's exons
 //but it does not cross any intron-exon boundary of tj
  int imax=ti.exons.Count()-1;
  int jmax=tj.exons.Count()-1;
  if (imax>0) GError("Error: bad unsplContained() call, 1st parameter must be single-exon transcript!\n");
  if (fuzzSpan) {
    int maxIntronOvl=dOvlSET ? 25 : 0;
    //int minovl = dOvlSET ? 5 : (int)(0.8 * ti.len()); //minimum overlap to declare "redundancy"
    for (int j=0;j<=jmax;j++) {
       bool exonOverlap=false;
       if (dOvlSET) {
    	   exonOverlap= (tj.exons[j]->overlapLen(ti.start-1, ti.end+1) > 0);
       } else {
    	   exonOverlap=(ti.overlapLen(tj.exons[j])>=0.8 * ti.len());
       }
       if (exonOverlap) {
          //must not overlap the introns
          if ((j>0 && ti.start+maxIntronOvl<tj.exons[j]->start)
             || (j<jmax && ti.end>tj.exons[j]->end+maxIntronOvl))
             return false;
          return true;
       }
    } //for each exon
  } else { // not fuzzSpan, strict containment required
    for (int j=0;j<=jmax;j++) {
        if (ti.end<=tj.exons[j]->end && ti.start>=tj.exons[j]->start)
          return true;
    }
 }
 return false;
}

GffObj* GffLoader::redundantTranscripts(GffObj& ti, GffObj&  tj) {
  // matchAllIntrons==true:  transcripts are considered "redundant" only if
  //                   they have the exact same number of introns and same splice sites (or none)
  //                   (single-exon transcripts should be also fully contained to be considered matching)
  // matchAllIntrons==false: an intron chain could be a subset of a "container" chain,
  //                   as long as no intron-exon boundaries are violated; also, a single-exon
  //                   transcript will be collapsed if it's contained in one of the exons of the another transcript
  // fuzzSpan==false: the genomic span of one transcript MUST BE contained in or equal with the genomic
  //                  span of the other
  //
  // fuzzSpan==true: then genomic spans of transcripts are no longer required to be fully contained
  //                 (i.e. they may extend each-other in opposite directions)

  //if redundancy is detected, the "bigger" transcript is returned (otherwise NULL is returned)
 int adj=dOvlSET ? 1 : 0;
 if (ti.start>tj.end+adj || tj.start>ti.end+adj ||
		 (tj.strand!='.' && ti.strand!='.' && tj.strand!=ti.strand)) return NULL; //no span overlap
 int imax=ti.exons.Count()-1;
 int jmax=tj.exons.Count()-1;
 GffObj* bigger=NULL;
 GffObj* smaller=NULL;
 if (matchAllIntrons) { //full intron chain match expected, or full containment for SET
   if (imax!=jmax) return NULL; //must have the same number of exons!
   if (ti.covlen>tj.covlen) {
      bigger=&ti;
      if (!fuzzSpan && (ti.start>tj.start || ti.end<tj.end))
        return NULL; //no containment
   }
   else { //ti.covlen<=tj.covlen
      bigger=&tj;
      if (!fuzzSpan && (tj.start>ti.start || tj.end<ti.end))
         return NULL; //no containment
   }
   //check that all introns really match
   for (int i=0;i<imax;i++) {
     if (ti.exons[i]->end!=tj.exons[i]->end ||
         ti.exons[i+1]->start!=tj.exons[i+1]->start) return NULL;
     }
   return bigger;
 }
 //--- matchAllIntrons==false: intron-chain containment is also considered redundancy
 int minlen=0;
 if (ti.covlen>tj.covlen) {
      if (tj.exons.Count()>ti.exons.Count()) {
          //exon count override
          bigger=&tj;
          smaller=&ti;
      } else {
          bigger=&ti;
          smaller=&tj;
      }
      //maxlen=ti.covlen;
      minlen=tj.covlen;
 } else { //tj has more bases covered
      if (ti.exons.Count()>tj.exons.Count()) {
          //exon count override
          bigger=&ti;
          smaller=&tj;
      } else {
          bigger=&tj;
          smaller=&ti;
      }
      //maxlen=tj.covlen;
      minlen=ti.covlen;
 }
 if (imax==0 && jmax==0) {
     //single-exon transcripts: if fuzzSpan, at least 80% of the shortest one must be overlapped by the other
     if (fuzzSpan) {
       if (dOvlSET) {
           return (ti.exons[0]->overlapLen(tj.exons[0]->start-1, tj.exons[0]->end+1)>0) ? bigger : NULL;
       } else {
          return (ti.exons[0]->overlapLen(tj.exons[0])>=minlen*0.8) ? bigger : NULL;
       }
     } else { //boundary containment required
       return (smaller->start>=bigger->start && smaller->end<=bigger->end) ? bigger : NULL;
     }
 }
 //containment is also considered redundancy
 if (smaller->exons.Count()==1) {
   //check if this single exon is contained in any of tj exons
   //without violating any intron-exon boundaries
   return (unsplContained(*smaller, *bigger) ? bigger : NULL);
 }

 //--- from here on: both are multi-exon transcripts: imax>0 && jmax>0
  if (ti.exons[imax]->start<tj.exons[0]->end ||
     tj.exons[jmax]->start<ti.exons[0]->end )
         return NULL; //intron chains do not overlap at all
 //checking full intron chain containment
 uint eistart=0, eiend=0, ejstart=0, ejend=0; //exon boundaries
 int i=1; //exon idx to the right of the current intron of ti
 int j=1; //exon idx to the right of the current intron of tj
 //find the first intron overlap:
 while (i<=imax && j<=jmax) {
    eistart=ti.exons[i-1]->end;
    eiend=ti.exons[i]->start;
    ejstart=tj.exons[j-1]->end;
    ejend=tj.exons[j]->start;
    if (ejend<eistart) { j++; continue; }
    if (eiend<ejstart) { i++; continue; }
    //we found an intron overlap
    break;
 }
 if (!fuzzSpan && (bigger->start>smaller->start || bigger->end < smaller->end)) return NULL;
 if ((i>1 && j>1) || i>imax || j>jmax) {
     return NULL; //either no intron overlaps found at all
                  //or it's not the first intron for at least one of the transcripts
 }
 if (eistart!=ejstart || eiend!=ejend) return NULL; //not an exact intron match
 int maxIntronOvl=dOvlSET ? 25 : 0;
 if (j>i) {
   //i==1, ti's start must not conflict with the previous intron of tj
   if (ti.start+maxIntronOvl<tj.exons[j-1]->start) return NULL;
   //comment out the line above if you just want "intron compatibility" (i.e. extension of intron chains )
   //so i's first intron starts AFTER j's first intron
   // then j must contain i, so i's last intron must end with or before j's last intron
   if (ti.exons[imax]->start>tj.exons[jmax]->start) return NULL;
 }
 else if (i>j) {
   //j==1, tj's start must not conflict with the previous intron of ti
   if (tj.start+maxIntronOvl<ti.exons[i-1]->start) return NULL;
   //comment out the line above for just "intronCompatible()" check (allowing extension of intron chain)
   //so j's intron chain starts AFTER i's
   // then i must contain j, so j's last intron must end with or before j's last intron
   if (tj.exons[jmax]->start>ti.exons[imax]->start) return NULL;
 }
 //now check if the rest of the introns overlap, in the same sequence
 i++;
 j++;
 while (i<=imax && j<=jmax) {
   if (ti.exons[i-1]->end!=tj.exons[j-1]->end ||
      ti.exons[i]->start!=tj.exons[j]->start) return NULL;
   i++;
   j++;
 }
 i--;
 j--;
 if (i==imax && j<jmax) {
   // tj has more introns to the right, check if ti's end doesn't conflict with the current tj exon boundary
   if (ti.end>tj.exons[j]->end+maxIntronOvl) return NULL;
   }
 else if (j==jmax && i<imax) {
   if (tj.end>ti.exons[i]->end+maxIntronOvl) return NULL;
   }
 return bigger;
}


int gseqCmpName(const pointer p1, const pointer p2) {
 return strcmp(((GenomicSeqData*)p1)->gseq_name, ((GenomicSeqData*)p2)->gseq_name);
}


void printLocus(GffLocus* loc, const char* pre) {
  if (pre!=NULL) fprintf(stderr, "%s", pre);
  GMessage(" [%d-%d] : ", loc->start, loc->end);
  GMessage("%s",loc->rnas[0]->getID());
  for (int i=1;i<loc->rnas.Count();i++) {
    GMessage(",%s",loc->rnas[i]->getID());
    }
  GMessage("\n");
}

void preserveContainedCDS(GffObj* tcontainer, GffObj* t) {
 //transfer contained CDS info to the container if t has a CDS but container does not
 if (!t->hasCDS()) return;
  if (!tcontainer->hasCDS())//no CDS info on container, just copy it from the contained
	 tcontainer->setCDS(t);
}

bool exonOverlap2Gene(GffObj* t, GffObj& g) {
	if (t->exons.Count()>0) {
		return t->exonOverlap(g.start, g.end);
	}
	else return g.overlap(*t);
}
bool GffLoader::placeGf(GffObj* t, GenomicSeqData* gdata) {
  bool keep=false;
  GTData* tdata=NULL;
  //int tidx=-1;
  /*
  if (debug) {
     GMessage(">>Placing transcript %s\n", t->getID());
     debugState=true;
     }
    else debugState=false;
   */
  //dumb TRNA case for RefSeq: gene parent link missing
  //try to restore it here; BUT this only works if gene feature comes first
  ////DEBUG ONLY:
  //if (strcmp(t->getID(),"id24448")==0) { //&& t->start==309180) {
  //	 GMessage("placeGf %s (%d, %d) (%d exons)\n", t->getID(),t->start, t->end, t->exons.Count());
  //}
  //GMessage("DBG>>Placing transcript %s(%d-%d, %d exons)\n", t->getID(), t->start, t->end, t->exons.Count());

  if (t->parent==NULL && t->isTranscript() && trAdoption) {
  	int gidx=gdata->gfs.Count()-1;
  	while (gidx>=0 && gdata->gfs[gidx]->end>=t->start) {
  		GffObj& g = *(gdata->gfs[gidx]);
  		//try to find a container gene object for this transcript
  		//if (g.isGene() && t->strand==g.strand && exonOverlap2Gene(t, g)) {
  		if (g.isGene() && (t->strand=='.' || t->strand==g.strand) && g.exons.Count()==0
  				  && t->start>=g.start && t->end<=g.end) {
  			if (g.children.IndexOf(t)<0)
  				g.children.Add(t);
  			keep=true;
  			if (tdata==NULL) {
  		       tdata=new GTData(t); //additional transcript data
  		       gdata->tdata.Add(tdata);
  			}
  			t->parent=&g;
  			//disable printing of gene if transcriptsOnly and --keep-genes wasn't given
  			if (transcriptsOnly && !keepGenes) {
  				T_NO_PRINT(g.udata); //tag it as non-printable
  				//keep gene ID and Name into transcript, when we don't print genes
  	  			const char* geneName=g.getAttr("Name");
  	  			if (t->getAttr("Name")==NULL && geneName) {
  	  				t->addAttr("Name", geneName);
  	  				if (t->getAttr("gene_name")==NULL)
  	  					t->addAttr("gene_name", geneName);
  	  			}
  	  			t->addAttr("geneID", g.getID());
  			}
  			break;
  		}
  		--gidx;
  	}
  }
  bool noexon_gfs=false;
  if (t->exons.Count()>0) { //treating this entry as a transcript
	gdata->rnas.Add(t); //added it in sorted order
	if (tdata==NULL) {
	   tdata=new GTData(t); //additional transcript data
	   gdata->tdata.Add(tdata);
	}
	keep=true;
  }
   else {
    if (t->isGene() || !this->transcriptsOnly) {
	   gdata->gfs.Add(t);
	   keep=true;
	   //GTData* tdata=new GTData(t); //additional transcript data
	   if (tdata==NULL) {
		   tdata=new GTData(t); //additional transcript data
		   gdata->tdata.Add(tdata);
	   }
	   noexon_gfs=true; //gene-like record, no exons defined
	   keep=true;
    } else {
       return false; //nothing to do with these non-transcript objects
    }
  }
  if (!doCluster) return keep;

  if (!keep) return false;

  //---- place into a locus
  if (dOvlSET && t->exons.Count()==1) {
	  //for single exon transcripts temporarily set the strand to '.'
	  //so we can check both strands for overlap/locus
      T_SET_OSTRAND(t->udata, t->strand);
      t->strand='.';
  }
  if (gdata->loci.Count()==0) {
       gdata->loci.Add(new GffLocus(t));
       return true; //new locus on this ref seq
  }
  //--- look for any existing loci overlapping t
  uint t_end=t->end;
  uint t_start=t->start;
  if (dOvlSET) {
	  t_end++;
	  t_start--;
  }
  int nidx=qsearch_gloci(t_end, gdata->loci); //get index of nearest locus starting just ABOVE t->end
  //GMessage("\tlooking up end coord %d in gdata->loci.. (qsearch got nidx=%d)\n", t->end, nidx);
  if (nidx==0) {
     //cannot have any overlapping loci
     //if (debug) GMessage("  <<no ovls possible, create locus %d-%d \n",t->start, t->end);
     gdata->loci.Add(new GffLocus(t));
     return true;
  }
  if (nidx==-1) nidx=gdata->loci.Count();//all loci start below t->end
  int lfound=0; //count of parent loci
  GArray<int> mrgloci(false);
  GList<GffLocus> tloci(true); //candidate parent loci to adopt this
  //if (debug) GMessage("\tchecking all loci from %d to 0\n",nidx-1);
  for (int l=nidx-1;l>=0;l--) {
      GffLocus& loc=*(gdata->loci[l]);
      if ((loc.strand=='+' || loc.strand=='-') && t->strand!='.'&& loc.strand!=t->strand) continue;
      if (t_start>loc.end) {
           if (t->start-loc.start>GFF_MAX_LOCUS) break; //give up already
           continue;
      }
      if (loc.start>t_end) {
               //this should never be the case if nidx was found correctly
               GMessage("Warning: qsearch_gloci found loc.start>t.end!(t=%s)\n", t->getID());
               continue;
      }

      if (loc.add_gfobj(t, dOvlSET)) {
         //will add this transcript to loc
         lfound++;
         mrgloci.Add(l);
         if (collapseRedundant && !noexon_gfs) {
           //compare to every single transcript in this locus
           for (int ti=0;ti<loc.rnas.Count();ti++) {
                 if (loc.rnas[ti]==t) continue;
                 GTData* odata=(GTData*)(loc.rnas[ti]->uptr);
                 //GMessage("  ..redundant check vs overlapping transcript %s\n",loc.rnas[ti]->getID());
                 GffObj* container=NULL;
                 if (odata->replaced_by==NULL &&
                      (container=redundantTranscripts(*t, *(loc.rnas[ti])))!=NULL) {
                     if (container==t) {
                        odata->replaced_by=t;
                        preserveContainedCDS(t, loc.rnas[ti]);
                     }
                     else {// t is being replaced by previously defined transcript
                        tdata->replaced_by=loc.rnas[ti];
                        preserveContainedCDS(loc.rnas[ti], t);
                     }
                 }
           }//for each transcript in the exon-overlapping locus
         } //if doCollapseRedundant
      } //overlapping locus
  } //for each existing locus
  if (lfound==0) {
      //overlapping loci not found, create a locus with only this mRNA
      int addidx=gdata->loci.Add(new GffLocus(t));
      if (addidx<0) {
         //should never be the case!
         GMessage("  WARNING: new GffLocus(%s:%d-%d) not added!\n",t->getID(), t->start, t->end);
      }
   }
   else { //found at least one overlapping locus
     lfound--;
     int locidx=mrgloci[lfound];
     GffLocus& loc=*(gdata->loci[locidx]);
     //last locus index found is also the smallest index
     if (lfound>0) {
       //more than one loci found parenting this mRNA, merge loci
       /* if (debug)
          GMessage(" merging %d loci \n",lfound);
       */
       for (int l=0;l<lfound;l++) {
          int mlidx=mrgloci[l];
          loc.addMerge(*(gdata->loci[mlidx]), t);
          gdata->loci.Delete(mlidx); //highest indices first, so it's safe to remove
       }
     }
     int i=locidx;
     while (i>0 && loc<*(gdata->loci[i-1])) {
       //bubble down until it's in the proper order
       i--;
       gdata->loci.Swap(i,i+1);
     }
  }//found at least one overlapping locus
  return true;
}

void collectLocusData(GList<GenomicSeqData>& ref_data, bool covInfo) {
	int locus_num=0;
	for (int g=0;g<ref_data.Count();g++) {
		GenomicSeqData* gdata=ref_data[g];
		for (int l=0;l<gdata->loci.Count();l++) {
			GffLocus& loc=*(gdata->loci[l]);
			GHash<int> gnames(true); //gene names in this locus
			//GHash<int> geneids(true); //Entrez GeneID: numbers
			GHash<int> geneids(true);
			int fstrand=0,rstrand=0,ustrand=0;
			for (int i=0;i<loc.rnas.Count();i++) {
				GffObj& t=*(loc.rnas[i]);
				char tstrand=(char) T_OSTRAND(t.udata);
				if (tstrand==0) tstrand=t.strand;
				if (tstrand=='+') fstrand++;
				 else if (tstrand=='-') rstrand++;
				   else ustrand++;
				GStr gname(t.getGeneName());
				if (!gname.is_empty()) {
					gname.upper();
					int* prevg=gnames.Find(gname.chars());
					if (prevg!=NULL) (*prevg)++;
					else gnames.Add(gname, new int(1));
				}
				GStr geneid(t.getGeneID());
				if (!geneid.is_empty())
					geneids.Add(geneid.chars());
				//parse GeneID xrefs, if any (RefSeq):
				/*
				GStr xrefs(t.getAttr("xrefs"));
				if (!xrefs.is_empty()) {
					xrefs.startTokenize(",");
					GStr token;
					while (xrefs.nextToken(token)) {
						token.upper();
						if (token.startsWith("GENEID:")) {
							token.cut(0,token.index(':')+1);
							int* prevg=geneids.Find(token.chars());
							if (prevg!=NULL) (*prevg)++;
							else geneids.Add(token, new int(1));
						}
					} //for each xref
				} //xrefs parsing
				*/
			}//for each transcript
            if ((fstrand>0 && rstrand>0) ||
            		 (fstrand==0 && rstrand==0)) loc.strand='.';
            else if (fstrand==0 && rstrand>0) loc.strand='-';
            else loc.strand='+';
			for (int i=0;i<loc.gfs.Count();i++) {
				GffObj& nt=*(loc.gfs[i]);
				if (nt.isGene()) {
					GStr gname(nt.getGeneName());
					if (!gname.is_empty()) {
						gname.upper();
						int* prevg=gnames.Find(gname.chars());
						if (prevg!=NULL) (*prevg)++;
						else gnames.Add(gname, new int(1));
					}
					GStr geneid(nt.getID());
					if (!geneid.is_empty()) {
						geneids.Add(geneid.chars(), new int(1));
					}
				}
				//parse GeneID xrefs, if any (RefSeq):
				/*
				GStr xrefs(nt.getAttr("xrefs"));
				if (!xrefs.is_empty()) {
					xrefs.startTokenize(",");
					GStr token;
					while (xrefs.nextToken(token)) {
						token.upper();
						if (token.startsWith("GENEID:")) {
							token.cut(0,token.index(':')+1);
							int* prevg=geneids.Find(token.chars());
							if (prevg!=NULL) (*prevg)++;
							else geneids.Add(token, new int(1));
						}
					} //for each xref
				} //xrefs parsing
				*/
			}//for each non-transcript (genes?)
			if (covInfo) {
				for (int m=0;m<loc.mexons.Count();m++) {
					if (loc.strand=='+')
						gdata->f_bases+=loc.mexons[m].len();
					else if (loc.strand=='-')
						gdata->r_bases+=loc.mexons[m].len();
					else gdata->u_bases+=loc.mexons[m].len();
				}
			}
			locus_num++;
			loc.locus_num=locus_num;
			if (gnames.Count()>0) { //collect all gene names associated to this locus
				gnames.startIterate();
				int* gfreq=NULL;
				char* key=NULL;
				while ((gfreq=gnames.NextData(key))!=NULL) {
					loc.gene_names.AddIfNew(new CGeneSym(key,*gfreq));
				}
			} //added collected gene_names
			if (geneids.Count()>0) { //collect all GeneIDs names associated to this locus
				geneids.startIterate();
				int* gfreq=NULL;
				char* key=NULL;
				while ((gfreq=geneids.NextData(key))!=NULL) {
					loc.gene_ids.AddIfNew(new CGeneSym(key,*gfreq));
				}
			}
		} //for each locus
	}//for each genomic sequence
}

void GffLoader::loadRefNames(GStr& flst) {
 //load the whole file and split by (' \t\n\r,'
	int64_t fsize=fileSize(flst.chars());
	if (fsize<0) GError("Error: could not get file size for %s !\n",
			flst.chars());
	GStr slurp("", fsize+1);
	//sanity check for file size?
	FILE* f=fopen(flst.chars(), "r");
	if (f==NULL)
		GError("Error: could not open file %s !\n", flst.chars());
	slurp.read(f, NULL);
	fclose(f);
	slurp.startTokenize(" ,;\t\r\n", tkCharSet);
	GStr refname;
	while (slurp.nextToken(refname)) {
		if (refname.is_empty()) continue;
		names->gseqs.addName(refname.chars());
	}
}

GenomicSeqData* getGSeqData(GList<GenomicSeqData>& seqdata, int gseq_id) {
	int i=-1;
	GenomicSeqData f(gseq_id);
	GenomicSeqData* gdata=NULL;
	if (seqdata.Found(&f,i)) gdata=seqdata[i];
	else { //entry not created yet for this genomic seq
		gdata=new GenomicSeqData(gseq_id);
		seqdata.Add(gdata);
	}
	return gdata;
}

void warnPseudo(GffObj& m) {
	GMessage("Info: pseudo gene/transcript record with ID=%s discarded.\n",m.getID());
}

void GffLoader::load(GList<GenomicSeqData>& seqdata, GFValidateFunc* gf_validate, GFFCommentParser* gf_parsecomment) {
	if (f==NULL) GError("Error: GffLoader::load() cannot be called before ::openFile()!\n");
	GffReader* gffr=new GffReader(f, this->transcriptsOnly, true); //not only mRNA features, sorted
	clearHeaderLines();
	gffr->showWarnings(verbose);
	//           keepAttrs   mergeCloseExons  noExonAttr
	gffr->gene2Exon(gene2exon);
	if (BEDinput) gffr->isBED(true);
	//if (TLFinput) gffr->isTLF(true);
	gffr->mergeCloseExons(mergeCloseExons);
	gffr->keepAttrs(fullAttributes, gatherExonAttrs, keep_AllExonAttrs);
	gffr->keepGenes(keepGenes);
	gffr->setIgnoreLocus(ignoreLocus);
	gffr->setRefAlphaSorted(this->sortRefsAlpha);
	if (keepGff3Comments && gf_parsecomment!=NULL) gffr->setCommentParser(gf_parsecomment);
	gffr->readAll();
	GVec<int> pseudoFeatureIds; //feature type: pseudo*
	GVec<int> pseudoAttrIds;  // attribute: [is]pseudo*=true/yes/1
	GVec<int> pseudoTypeAttrIds;  // attribute: *_type=pseudo*

	if (this->noPseudo) {
		GffNameList& fnames = GffObj::names->feats; //gffr->names->feats;
		for (int i=0;i<fnames.Count();i++) {
			char* n=fnames[i]->name;
			if (startsWith(n, "pseudo")) {
				pseudoFeatureIds.Add(fnames[i]->idx);
			}
		}
		GffNameList& attrnames = GffObj::names->attrs;//gffr->names->attrs;
		for (int i=0;i<attrnames.Count();i++) {
			char* n=attrnames[i]->name;
			if (endsiWith(n, "type")) {
				pseudoTypeAttrIds.Add(attrnames[i]->idx);
			}// else {
			char* p=strifind(n, "pseudo");
			if (p==n || (p==n+2 && tolower(n[0])=='i' && tolower(n[1])=='s') ||
					(p==n+3 && startsiWith(n, "is_")) ) {
				pseudoAttrIds.Add(attrnames[i]->idx);
			}
			//}
		}
	}

	//int redundant=0; //redundant annotation discarded
	if (verbose) GMessage("   .. loaded %d genomic features from %s\n", gffr->gflst.Count(), fname.chars());
	//int rna_deleted=0;
	//add to GenomicSeqData, adding to existing loci and identifying intron-chain duplicates
	for (int k=0;k<gffr->gflst.Count();k++) {
		GffObj* m=gffr->gflst[k];
		if (strcmp(m->getFeatureName(), "locus")==0 &&
				m->getAttr("transcripts")!=NULL) {
			continue; //discard locus meta-features
		}
		if (this->noPseudo) {
			bool is_pseudo=false;
			for (int i=0;i<pseudoFeatureIds.Count();++i) {
				if (pseudoFeatureIds[i]==m->ftype_id) {
					is_pseudo=true;
					break;
				}
			}
			if (is_pseudo) {
				if (verbose) warnPseudo(*m);
				continue;
			}
			for (int i=0;i<pseudoAttrIds.Count();++i) {
				char* attrv=NULL;
				if (m->attrs!=NULL) attrv=m->attrs->getAttr(pseudoAttrIds[i]);
				if (attrv!=NULL) {
					char fc=tolower(attrv[0]);
					if (fc=='t' || fc=='y' || fc=='1') {
						is_pseudo=true;
						break;
					}
				}
			}
			if (is_pseudo) {
				if (verbose) warnPseudo(*m);
				continue;
			}
			//  *type=*_pseudogene
            //find all attributes ending with _type and have value like: *_pseudogene
			for (int i=0;i<pseudoTypeAttrIds.Count();++i) {
				char* attrv=NULL;
				if (m->attrs!=NULL) attrv=m->attrs->getAttr(pseudoTypeAttrIds[i]);
				if (attrv!=NULL &&
						(startsWith(attrv, "pseudogene") || endsWith(attrv, "_pseudogene")) ) {
					is_pseudo=true;
					break;
				}
			}
			if (is_pseudo) {
				if (verbose) warnPseudo(*m);
				continue;
			}
		} //pseudogene detection requested
		char* rloc=m->getAttr("locus");
		if (rloc!=NULL && startsWith(rloc, "RLOC_")) {
			m->removeAttr("locus", rloc);
		}
		if (forceExons) {
			m->subftype_id=gff_fid_exon;
		}
		//GList<GffObj> gfadd(false,false); -- for gf_validate()?
		if (gf_validate!=NULL && !(*gf_validate)(m, NULL)) {
			continue;
		}
		m->isUsed(true); //so the gffreader won't destroy it
		GenomicSeqData* gdata=getGSeqData(seqdata, m->gseq_id);
		bool keep=placeGf(m, gdata);
		if (!keep) {
			m->isUsed(false);
			//DEBUG
			//GMessage("Feature %s(%d-%d) is going to be discarded..\n",m->getID(), m->start, m->end);
		}
	} //for each read gffObj
	//if (verbose) GMessage("  .. %d records from %s clustered into loci.\n", gffr->gflst.Count(), fname.chars());
	//if (f && f!=stdin) { fclose(f); f=NULL; }
	delete gffr;
}
