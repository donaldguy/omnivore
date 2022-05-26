/* eslint-disable @typescript-eslint/no-unused-vars */
import {
  ResolverFn,
  UploadFileRequestResult,
  MutationUploadFileRequestArgs,
  UploadFileStatus,
  UploadFileRequestErrorCode,
  ArticleSavingRequestStatus,
} from '../../generated/graphql'
import { WithDataSourcesContext } from '../types'
import {
  generateUploadSignedUrl,
  generateUploadFilePathName,
} from '../../utils/uploads'
import path from 'path'
import normalizeUrl from 'normalize-url'
import { analytics } from '../../utils/analytics'
import { env } from '../../env'
import { createPage, getPageByParam, updatePage } from '../../elastic/pages'
import { PageType } from '../../elastic/types'
import { generateSlug } from '../../utils/helpers'

export const uploadFileRequestResolver: ResolverFn<
  UploadFileRequestResult,
  unknown,
  WithDataSourcesContext,
  MutationUploadFileRequestArgs
> = async (_obj, { input }, ctx) => {
  const { models, kx, claims } = ctx
  let uploadFileData: { id: string | null } = {
    id: null,
  }

  if (!claims?.uid) {
    return { errorCodes: [UploadFileRequestErrorCode.Unauthorized] }
  }

  analytics.track({
    userId: claims.uid,
    event: 'file_upload_request',
    properties: {
      url: input.url,
      env: env.server.apiEnv,
    },
  })

  let title: string
  let fileName: string
  try {
    const url = normalizeUrl(new URL(input.url).href, {
      stripHash: true,
      stripWWW: false,
    })
    title = decodeURI(path.basename(new URL(url).pathname, '.pdf'))
    fileName = decodeURI(path.basename(new URL(url).pathname)).replace(
      /[^a-zA-Z0-9-_.]/g,
      ''
    )

    if (!fileName) {
      fileName = 'content.pdf'
    }
  } catch {
    return { errorCodes: [UploadFileRequestErrorCode.BadInput] }
  }

  uploadFileData = await models.uploadFile.create({
    url: input.url,
    userId: claims.uid,
    fileName: fileName,
    status: UploadFileStatus.Initialized,
    contentType: input.contentType,
  })

  if (uploadFileData.id) {
    const uploadFilePathName = generateUploadFilePathName(
      uploadFileData.id,
      fileName
    )
    const uploadSignedUrl = await generateUploadSignedUrl(
      uploadFilePathName,
      input.contentType
    )

    if (input.createPageEntry) {
      let page = await getPageByParam({
        userId: claims.uid,
        url: input.url,
      })
      if (page) {
        await updatePage(page.id, {
          savedAt: new Date(),
          archivedAt: null,
        }, ctx)
      } else {
        const pageId = await createPage(
          {
            url: input.url,
            id: input.clientRequestId || '',
            userId: claims.uid,
            title: title,
            hash: uploadFilePathName,
            content: '',
            pageType: PageType.File,
            uploadFileId: uploadFileData.id,
            slug: generateSlug(uploadFilePathName),
            createdAt: new Date(),
            savedAt: new Date(),
            readingProgressPercent: 0,
            readingProgressAnchorIndex: 0,
            state: ArticleSavingRequestStatus.Processing,
          },
          ctx
        )
        if (!pageId) {
          return { errorCodes: [UploadFileRequestErrorCode.FailedCreate] }
        }
      }
    }

    return { id: uploadFileData.id, uploadSignedUrl }
  } else {
    return { errorCodes: [UploadFileRequestErrorCode.FailedCreate] }
  }
}
