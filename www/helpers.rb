require 'cgi'
require 'rbbt/sources/entrez'
require 'rbbt/sources/kegg'
require 'rbbt/sources/cancer'


def check_logged_user(user,password)
  
  $users = [{:user => 'mhidalgo', :password => '123qwe', :experiments => ['Exclusive','Metastasis','NoMetastasis','Raquel','Raquel_Patient']},{:user => 'preal', :password => '123qwe', :experiments => ['1035','Esp66']}]
  
  if session[:user].include? :user
    return true;
  else
    if (user && password)
       $users.each do |u|
        if (user == u[:user] && password == u[:password])
          session[:user] = u
          return true
        end
       end  
    end 
  end  
  return false    
end

def entrez_info(entrez)
  marshal_cache('entrez_info', entrez) do
    Entrez.get_gene(entrez)
  end
end

def first(array)
  (array || [""]).first
end

def genecard_trigger(text, ensembl)
  gname = [gname] unless Array === gname
  if gname.last =~ /UNKNOWN/
    text
  else
    "<a class='genecard_trigger' href='/ajax/genecard' onclick='update_genecard(\"#{ensembl}\");return(false);'>#{text}</a>"
  end
end

def list_summary(list)
  return list unless Array === list
  code = Digest::MD5.hexdigest(list.inspect)
  if list.length < 3 
    list * ', '
  else
    list[0..1] * ', ' + ', ' +
      "<a id='#{code}' class=expand href='' value='#{CGI.escapeHTML(list * ', ').gsub(/'/,'"')}' onclick='expand_field(\"#{code}\");return(false)'>#{list.size - 2} more ...<a>"
  end
end


def mutation_severity_summary(mutation)
  count = 0

  count += 1 if first(mutation["SIFT:Prediction"])
  count += 1 if first(mutation["SNP&GO:Disease?"]) == 'Disease'
  count += 1 if first(mutation["Polyphen:prediction"]) =~ /damaging/

  count
end

def kegg_summary(pathways, html = true)
  return [] if pathways.nil?
  pathways.collect do |code|
    desc = $kegg[code]["Pathway Name"].sub(/- Homo sapiens.*/,'')
    cancer = ''
    if html
      entries = $anais[code]
      entries.zip_fields.each do |cancer, type, score, desc2|
      #TSV.zip_fields($anais[code]).each do |p|
      #  cancer, type, score, desc2 = p
        css_class = (score != nil and score.to_f <= 0.1)?'red':'green';
        cancer += " <span class='#{ css_class } cancertype'>[#{ cancer }]</span>"
      end if entries
      "<a target='_blank' href='http://www.genome.jp/kegg-bin/show_pathway?#{code}'>#{desc} #{ cancer }</a>"
    else
      desc 
    end 
  end 
end


def matador_summary(matador_drugs, html = true)
  return [] if matador_drugs.empty?
  matador_drugs.collect do |d|
    name, id, score, annot, mscore, mannot = d
    if html
      css_class = (mannot == 'DIRECT')?'red':'normal';
      "<a target='_blank' href='http://matador.embl.de/drugs/#{id}/'>#{name}</a> [M]"
    else
      name
    end
  end  
end

def pharmagkb_summary(pgkb_drugs, html = true)
  return [] if pgkb_drugs.nil?
  pgkb_drugs.collect do |d|
    if html
      "<a target='_blank' href='http://www.pharmgkb.org/do/serve?objCls=Drug&objId=#{d.first}'>#{$PharmaGKB_drug_index[d.first]["Drug Name"]}</a> [PGKB]"
    else
      $PharmaGKB_drug_index[d.first]["Drug Name"]
    end
  end
end

def nci_drug_summary(nci_drugs, html = true)
  return [] if nci_drugs.nil?
  nci_drugs.reject{|d| d.first.empty?}.collect do |d|
    if html
      "<a target='_blank' href='http://ncit.nci.nih.gov/ncitbrowser/pages/concept_details.jsf?dictionary=NCI%20Thesaurus&type=properties&code=#{d[1]}'>#{d.first}</a> [NCI]"
    else
      d.first
    end
  end.uniq
end

def cancer_genes_summary(cancers, html = true)
  return [] if cancers.nil?
  cancers.first.collect do |c|
    if html
      "<span>#{c} [C]</span>"
    else
      c
    end
  end + 
  cancers.last.collect do |c|
    if html
      "<span>#{c} [NCI]</span>"
    else
      c
    end
  end
end

def pathway_details_summary(kegg_pathways)
  return 'No pathways found' if kegg_pathways.nil?
  out =  ''
  kegg_pathways.collect do |code|
    desc = $kegg[code]["Pathway Name"].sub(/- Homo sapiens.*/,'')
    out += "<a href='http://www.genome.jp/kegg/pathway/hsa/#{code}.png'  class='top_up'><img src='http://www.genome.jp/kegg/pathway/hsa/#{code}.png' style='height:50px;float:left;margin-right:10px;margin-botton:10px;' title='Click to enlarge'/></a>";
    out += "<p>#{desc} <a target='_blank' href='http://www.genome.jp/kegg-bin/show_pathway?#{code}'>[+]</a></p>"
    name = ''
    cancers = TSV.zip_fields($anais[code])
    if cancers.any?
      out += '<p>This pathway has more mutations than expected by chance in the following tumour types</p>'
      cancers.each do |p|
        cancer, type, score, desc2 = p
        css_class = (score != nil and score.to_f <= 0.1)?'red':'green';
        out += " <span class='#{ css_class } cancertype'>[#{ cancer }]</span> "
      end
    end
    out += '<div class="clearfix"></div>'
    out += '<div style="height:10px;">&nbsp;</div>'
  end
  out
end

def drug_details_summary(matador_drugs, pgkb_drugs, nci_drugs)
  return 'No drugs found' if (!(matador_drugs || []).any? && !(pgkb_drugs || []).any? && !(nci_drugs || []).any? )
  out =  ''
  if ((matador_drugs || []).any?)
    matadorOut = '<dt><b>MATADOR drugs (Full list)</b></dt><dd>'
    matador_drugs_a = matador_drugs.collect do |d|
      name, id, score, annot, mscore, mannot, mmscore, mmannot = d
      direct = [annot, mannot, mmannot].select{|a| a == 'DIRECT'}.any?
      css_class = direct ? 'red' : 'normal';
      "<a target='_blank' class='#{css_class}' href='http://matador.embl.de/drugs/#{id}/'>#{name}</a>"
    end
    matadorOut << matador_drugs_a * ', '
    matadorOut << '</dd>'
    out << matadorOut  
  end  

  if ((pgkb_drugs || []).any?)
    pgkbOut = '<dt><b>PharmaGKB drugs (Full list)</b></dt><dd>'
    pgkb_drugs_a = pgkb_drugs.collect do |d|
      "<a target='_blank' href='http://www.pharmgkb.org/do/serve?objCls=Drug&objId=#{d.first}'>#{$PharmaGKB_drug_index[d.first]}</a>"
    end
    pgkbOut << pgkb_drugs_a * ', '
    pgkbOut << '</dd>'
    out << pgkbOut  
  end  

  if ((nci_drugs || []).any?)
    nciOut = '<dt><b>NCI  drugs (Full list)</b></dt><dd>'

    nci_drugs_a = nci_drugs.reject{|d| d.first.empty?}.collect do |d|
      "<a target='_blank' href='http://ncit.nci.nih.gov/ncitbrowser/pages/concept_details.jsf?dictionary=NCI%20Thesaurus&type=properties&code=#{d[1]}'>#{d.first}</a>"
    end.uniq

    nciOut << nci_drugs_a * ', '
    out << nciOut
  end    
  out     
end

def patients_details_top5_patient_list(info, gained = true)
  return "Sorry, no information about patients found" if info.nil?
  field_types = %w(type probability expression top5_loss top5_gain)
  plist  = []

  patient_info = {}
  info.fields.each do |field|
    if field =~ /(.*?)_(#{field_types * "|"})/
      patient      = $1
      field_type   = $2
      patient_info[patient] ||= {}
      patient_info[patient][field_type] = info[field]
    end
  end

  patient_info.select{|name, patient| (patient['type'] == 'Gain') == gained }.sort_by{|name, patient| name}.collect do |name,patient|
    if patient['top5_gain'].first != "0"
      plist << '<span class="gain">' + name + '</span>'
    elsif patient['top5_loss'].first != "0"
      plist << '<span class="loss">' + name + '</span>'
    else
      plist << name
    end
  end    
  plist * ', '    
end

def patients_details_expression(info)
  return "Sorry, no information about patients found" if info.nil?
  field_types = %w(type probability expression top5_loss top5_gain)
  plist  = []

  patient_info = {}
  info.fields.each do |field|
    if field =~ /(.*?)_(#{field_types * "|"})/
      patient      = $1
      field_type   = $2
      patient_info[patient] ||= {'pos' => patient_info.size.to_s}
      patient_info[patient][field_type] = info[field]
    end
  end

  out  = 'var expression = [';
  points = []
  patient_info.sort_by{|name, patient| name }.collect do |name,patient|
    points << '["' + patient['pos'] + '",' + patient['expression'].first + ']'
  end 
  out << points * ',' 
  out << '];'
end

